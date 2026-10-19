import Foundation
import NaturalLanguage
import SuperFlowCore

/// Hallucination guards for silence and noise (local-models.md §2.12), applied to every engine's output.
public enum TranscriptGuard {
    /// Faster than anyone speaks: the decoder is looping or inventing text.
    public static let maximumCharactersPerSecond = 25.0

    /// What Whisper says over silence and music (compared case-insensitively, without surrounding punctuation).
    public static let phantoms: Set<String> = [
        "thank you", "thank you very much", "thanks for watching", "thank you for watching", "thanks for listening",
        "please subscribe", "like and subscribe", "you", "bye", "bye bye", "music", "applause", "silence", "blank audio",
        "subtitles by the amaraorg community", "subtitles by", "transcribed by", "beep",
    ]

    /// Bracketed non-speech tags engines emit: "[BLANK_AUDIO]", "(music)", "[Music]", "*laughs*".
    public static func stripTags(_ text: String) -> String {
        let pattern = #"\[[^\]]*\]|\([^)]*(music|applause|silence|laugh|blank|noise|inaudible)[^)]*\)|\*[^*]*\*"#
        let stripped = text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        return stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The same n-gram back to back: three times for phrases (n ≥ 2), five for a single word ("no, no, no" is speech).
    public static func isRepetitive(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace }).map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard words.count >= 5 else { return false }
        for n in 1...min(8, words.count / 3) {
            let needed = n == 1 ? 5 : 3
            var i = 0
            while i + n * needed <= words.count {
                var repeats = 1
                while i + (repeats + 1) * n <= words.count, words[i + repeats * n..<i + (repeats + 1) * n] == words[i..<i + n] { repeats += 1 }
                if repeats >= needed { return true }
                i += 1
            }
        }
        return false
    }

    public static func isTooFast(_ text: String, speechSeconds: TimeInterval) -> Bool {
        let characters = text.filter { !$0.isWhitespace }.count
        return characters > 12 && Double(characters) / max(speechSeconds, 0.25) > maximumCharactersPerSecond
    }

    public static func isPhantom(_ text: String) -> Bool {
        let key = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return phantoms.contains(key)
    }

    /// The text to keep: tags stripped, nothing when it loops, runs too fast, or is a known phantom over quiet audio.
    public static func accept(_ text: String, speechSeconds: TimeInterval, quiet: Bool) -> String {
        let cleaned = stripTags(text)
        if cleaned.isEmpty || isRepetitive(cleaned) || isTooFast(cleaned, speechSeconds: speechSeconds) { return "" }
        if quiet, isPhantom(cleaned) { return "" }
        return cleaned
    }

    /// Mean level of the speech in dBFS; under −45 dBFS counts as quiet for the phantom check.
    public static func isQuiet(_ samples: ArraySlice<Float>) -> Bool {
        guard !samples.isEmpty else { return true }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return 10 * log10(sum / Float(samples.count) + 1e-12) < -45
    }
}

/// The language of recognised text (Parakeet reports none), for `Transcript.language` and the "Speaking a different
/// language?" hint (local-models.md §2.10). Too little text is not judged.
public enum TextLanguage {
    public static func identify(_ text: String, among candidates: [String]) -> (language: String, confidence: Double) {
        let allowed = candidates.map(SupportedLanguages.base)
        let fallback = allowed.first ?? "en"
        guard text.split(whereSeparator: \.isWhitespace).count >= 3 else { return (fallback, 1) }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 40)
        let scored = hypotheses.map { (SupportedLanguages.base($0.key.rawValue), $0.value) }
        let pool = allowed.isEmpty ? scored : scored.filter { allowed.contains($0.0) }
        guard let best = pool.max(by: { $0.1 < $1.1 }) else { return (fallback, 0) }
        return (best.0, best.1)
    }
}

/// The Whisper initial prompt (local-models.md §2.11): "Vocabulary: …." with up to 50 terms (the caller orders them:
/// starred, recent, app context), then the end of the previous text for continuity; ≈ 224 tokens at most.
public enum WhisperPrompt {
    public static let maximumTerms = 50
    public static let maximumCharacters = 800

    public static func make(vocabulary: [String], previousText: String?) -> String? {
        var seen: Set<String> = []
        let terms = vocabulary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(maximumTerms)
        var parts: [String] = []
        var budget = maximumCharacters
        if !terms.isEmpty {
            var line = "Vocabulary: "
            for term in terms where line.count + term.count + 2 < budget * 2 / 3 {
                line += (line.hasSuffix(": ") ? "" : ", ") + term
            }
            parts.append(line + ".")
            budget -= line.count + 1
        }
        if let previous = previousText?.trimmingCharacters(in: .whitespacesAndNewlines), !previous.isEmpty, budget > 40 {
            parts.append(String(previous.suffix(budget - 1)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

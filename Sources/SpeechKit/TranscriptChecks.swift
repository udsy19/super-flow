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

/// The writing systems of the requested languages: a transcript mostly in a script none of them uses is a decoder that
/// wandered off on quiet audio ("これだけ" from a quiet English microphone), not speech. Latin always fits (names,
/// brands and English words turn up in every language); auto-detect (no languages) and unknown codes accept anything.
public enum TranscriptScript {
    public enum Script: Hashable, Sendable {
        case latin, greek, cyrillic, armenian, hebrew, arabic, devanagari, bengali, gurmukhi, gujarati, tamil, telugu, kannada,
             malayalam, sinhala, thai, lao, tibetan, myanmar, georgian, ethiopic, khmer, hangul, kana, han, other
    }

    /// Text whose letters are at least this share in other scripts doesn't fit.
    public static let foreignShare = 0.3

    /// Languages written in something other than (or besides) Latin; every other code Parakeet or Whisper knows is Latin.
    static let nonLatin: [String: Set<Script>] = [
        "be": [.cyrillic], "bg": [.cyrillic], "kk": [.cyrillic], "mk": [.cyrillic], "mn": [.cyrillic], "ru": [.cyrillic],
        "sr": [.cyrillic], "tg": [.cyrillic], "tt": [.cyrillic], "uk": [.cyrillic], "ba": [.cyrillic], "el": [.greek],
        "hy": [.armenian], "he": [.hebrew], "yi": [.hebrew], "ar": [.arabic], "fa": [.arabic], "ps": [.arabic], "sd": [.arabic],
        "ur": [.arabic], "hi": [.devanagari], "mr": [.devanagari], "ne": [.devanagari], "sa": [.devanagari], "bn": [.bengali],
        "as": [.bengali], "pa": [.gurmukhi], "gu": [.gujarati], "ta": [.tamil], "te": [.telugu], "kn": [.kannada],
        "ml": [.malayalam], "si": [.sinhala], "th": [.thai], "lo": [.lao], "bo": [.tibetan], "my": [.myanmar], "ka": [.georgian],
        "am": [.ethiopic], "km": [.khmer], "ja": [.kana, .han], "zh": [.han], "yue": [.han], "ko": [.hangul, .han],
    ]

    /// The scripts the languages are written in, Latin included; nil when any of them is unknown (anything fits).
    static func scripts(for languages: [String]) -> Set<Script>? {
        var scripts: Set<Script> = [.latin]
        for language in languages.map(SupportedLanguages.base) {
            if let own = nonLatin[language] { scripts.formUnion(own); continue }
            guard SupportedLanguages.whisper.contains(language) || SupportedLanguages.parakeet.contains(language) else { return nil }
        }
        return scripts
    }

    /// Whether the text is written the way the languages are: under `foreignShare` of its letters in other scripts.
    public static func fits(_ text: String, languages: [String]) -> Bool {
        guard !languages.isEmpty, let allowed = scripts(for: languages) else { return true }
        var letters = 0, foreign = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if !allowed.contains(script(of: scalar)) { foreign += 1 }
        }
        return letters == 0 || Double(foreign) < foreignShare * Double(letters)
    }

    static func script(of scalar: Unicode.Scalar) -> Script {
        switch scalar.value {
        case 0x41...0x24F, 0x250...0x2AF, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xFF21...0xFF5A: .latin
        case 0x370...0x3FF, 0x1F00...0x1FFF: .greek
        case 0x400...0x52F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: .cyrillic
        case 0x530...0x58F: .armenian
        case 0x590...0x5FF, 0xFB1D...0xFB4F: .hebrew
        case 0x600...0x6FF, 0x750...0x77F, 0x8A0...0x8FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: .arabic
        case 0x900...0x97F: .devanagari
        case 0x980...0x9FF: .bengali
        case 0xA00...0xA7F: .gurmukhi
        case 0xA80...0xAFF: .gujarati
        case 0xB80...0xBFF: .tamil
        case 0xC00...0xC7F: .telugu
        case 0xC80...0xCFF: .kannada
        case 0xD00...0xD7F: .malayalam
        case 0xD80...0xDFF: .sinhala
        case 0xE00...0xE7F: .thai
        case 0xE80...0xEFF: .lao
        case 0xF00...0xFFF: .tibetan
        case 0x1000...0x109F: .myanmar
        case 0x10A0...0x10FF, 0x2D00...0x2D2F: .georgian
        case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF: .hangul
        case 0x1200...0x139F: .ethiopic
        case 0x1780...0x17FF: .khmer
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: .kana
        case 0x3005...0x3007, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FFFF: .han
        default: .other
        }
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

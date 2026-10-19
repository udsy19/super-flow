import Foundation
import NaturalLanguage
import SuperFlowCore

/// Checks on what the LLM wrote (local-models.md §3.6). Any failure means the rules-only text is inserted instead, with
/// the reason as the skip reason; prompt injection beat every model tested (§3.7), so these are not optional.
enum Guardrails {
    /// Chat-template tokens and prompt tags that must never reach the text field.
    static let leaks = ["<|im_start|>", "<|im_end|>", "<|endoftext|>", "<think>", "</think>", "<transcript", "</transcript",
                        "<dictionary", "</dictionary", "<before_cursor", "</before_cursor", "<instruction", "</instruction", "<text>", "</text>"]
    /// How assistants open a reply (answering or refusing instead of cleaning).
    static let assistantOpeners = ["sure", "here's", "here is", "here are", "i can't", "i cannot", "i can not", "i'm sorry", "i am sorry",
                                   "as an ai", "certainly", "of course", "i'd be happy", "i would be happy", "okay, here", "ok, here",
                                   "the cleaned", "cleaned text", "i won't", "i will not", "unfortunately"]
    private static let placeholder = try! NSRegularExpression(pattern: "⟦S\\d+⟧")
    private static let stopWords: Set<String> = Lexicon.continuationWords.union([
        "i", "me", "him", "them", "us", "am", "being", "an", "than", "such", "only", "own", "same", "both", "each", "few", "nor",
        "off", "out", "up", "down", "again", "further", "once", "why", "whom", "s", "t", "d", "ll", "m", "re", "ve", "don't",
        "can't", "won't", "isn't", "aren't", "wasn't", "weren't", "doesn't", "didn't", "haven't", "hasn't", "i'm", "i'll", "i've",
        "i'd", "that's", "there's", "what's", "let's", "got", "get", "going", "gonna", "wanna", "say", "said", "one", "think",
        "know", "well", "oh", "hey", "hi", "hello",
    ])

    /// Bounds per cleanup level: output/input word ratio, the share of new content words allowed, and the share of the
    /// input's content words that may go missing (cleanup-quality.md §5 P0.4). Medium and high rephrase by design, so they
    /// tolerate more new and missing words; high also shortens.
    private static func limits(_ level: CleanupLevel) -> (ratio: ClosedRange<Double>, novel: Double, dropped: Double) {
        switch level {
        case .none, .light: (0.5...1.25, 0.15, 0.2)
        case .medium: (0.5...1.25, 0.25, 0.35)
        case .high: (0.35...1.25, 0.4, 0.6)
        }
    }
    /// Words a speaker corrects themselves with, in the languages the speech engines write (accent-folded). A correction
    /// the rules could not resolve (another language, an unusual marker) legitimately drops the words it replaces.
    private static let correctionMarkers: Set<String> = ["no", "non", "nein", "nee", "sorry", "actually", "wait", "attends", "perdon",
                                                         "scusa", "mean", "meant", "rather", "scratch", "oops"]
    /// Repeats the speaker means ("she had had enough"): the model must not tidy them away (§5 P2.11).
    private static let meantRepeats: Set<String> = ["had", "that", "bye"]

    /// The cleaned output, or why it is rejected.
    static func checkCleanup(_ output: String, input: String, level: CleanupLevel, hints: [String]) -> Result<String, Rejection> {
        let text = strippedThinking(output)
        if text.isEmpty { return .failure(Rejection(.emptyOutput)) }
        if let leak = leaks.first(where: { text.contains($0) }) { return .failure(Rejection(.hallucination, "leaked \(leak)")) }
        if placeholders(in: text) != placeholders(in: input) { return .failure(Rejection(.hallucination, "placeholders changed")) }

        let inputWords = words(input), outputWords = words(text)
        if let opener = assistantOpeners.first(where: { text.lowercased().hasPrefix($0) }),
           !input.lowercased().hasPrefix(opener.split(separator: " ").first.map(String.init) ?? opener) {
            return .failure(Rejection(.hallucination, "assistant reply"))
        }
        let (ratio, novelShare, droppedShare) = limits(level)
        let n = Double(inputWords.count), m = Double(outputWords.count)
        let upper = max((ratio.upperBound * n).rounded(.up), n + 2)
        // Spoken numbers shrink when written ("five five five, one two three…" → 555-123-…): a run of number words and a
        // written number each count once for the lower bound.
        if Double(numbersCollapsed(outputWords)) < (ratio.lowerBound * Double(numbersCollapsed(inputWords))).rounded(.down) || m > upper {
            return .failure(Rejection(.hallucination, "word ratio \(outputWords.count)/\(inputWords.count)"))
        }
        let known = (inputWords + hints.flatMap { words($0) }).reduce(into: Set<String>()) { $0.formUnion(stems($1)) }
        let content = outputWords.filter { !stopWords.contains($0) && !NumberWords.isNumeric($0) }
        let novel = content.filter { stems($0).isDisjoint(with: known) }
        if Double(novel.count) > max(1, novelShare * Double(content.count)) {
            return .failure(Rejection(.hallucination, "new words: \(novel.prefix(5).joined(separator: ", "))"))
        }
        // Nothing the user said may quietly disappear: a clause the model left out passes the length check on its own.
        let written = outputWords.reduce(into: Set<String>()) { $0.formUnion(stems($1)) }
        let said = inputWords.filter { !stopWords.contains($0) && !NumberWords.isNumeric($0) }
        let lost = said.filter { stems($0).isDisjoint(with: written) }
        let corrected = !correctionMarkers.isDisjoint(with: inputWords)
        let allowed = corrected ? max(3, max(droppedShare, 0.35) * Double(said.count)) : max(2, droppedShare * Double(said.count))
        if Double(lost.count) > allowed {
            return .failure(Rejection(.hallucination, "dropped words: \(lost.prefix(5).joined(separator: ", "))"))
        }
        if let repeated = doubled(inputWords).subtracting(doubled(outputWords)).first {
            return .failure(Rejection(.hallucination, "dropped \"\(repeated) \(repeated)\""))
        }
        // A dictated question comes back as a question, not as an answer.
        if let first = inputWords.first, Lexicon.isQuestion(firstWord: first, secondWord: inputWords.dropFirst().first),
           !text.contains("?"), outputWords.first != first {
            return .failure(Rejection(.hallucination, "answered a question"))
        }
        // Never translated (cleanup-quality.md §9): both sides clearly in one language each, and not the same one.
        if inputWords.count >= 5, let said = clearLanguage(input), let written = clearLanguage(text), said != written {
            return .failure(Rejection(.hallucination, "language changed: \(said.rawValue) → \(written.rawValue)"))
        }
        return .success(text)
    }

    /// Transform output: the leaks and preambles are removed, and the length must suit the task.
    static func checkTransform(_ output: String, input: String, intent: CommandIntent) -> Result<String, TransformError> {
        var text = strippedThinking(output)
        text = text.replacingOccurrences(of: #"^\s*<text>|</text>\s*$"#, with: "", options: .regularExpression)
        // "Sure! Here's the formal version:" on a line of its own.
        if let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
           firstLine.hasSuffix(":"), assistantOpeners.contains(where: { firstLine.lowercased().hasPrefix($0) }) {
            text = String(text.dropFirst(firstLine.count))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, let first = text.first, let last = text.last, first == "\"" && last == "\"" || first == "“" && last == "”",
           !(input.first == first) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty { return .failure(.emptyResponse) }
        if leaks.contains(where: { text.contains($0) }) { return .failure(.failed) }
        if let limit = intent.maxOutputWords(Dictation.countWords(input)), Dictation.countWords(text) > limit { return .failure(.failed) }
        return .success(text)
    }

    struct Rejection: Error, Equatable {
        var reason: CleanupSkipReason
        var detail: String
        init(_ reason: CleanupSkipReason, _ detail: String = "") { self.reason = reason; self.detail = detail }
    }

    /// Removes a leading `<think>…</think>` block (empty when thinking is off) and surrounding whitespace.
    static func strippedThinking(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<think>"), let end = text.range(of: "</think>") {
            text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func placeholders(in text: String) -> [String] {
        placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted()
    }

    /// Lower-cased, accent-folded words, without list markers ("1.", "- ") so a list counts its items' words.
    static func words(_ text: String) -> [String] {
        let unlisted = text.replacingOccurrences(of: #"(?m)^[ \t]*(?:\d+[.)]|[-•*])[ \t]+"#, with: "", options: .regularExpression)
        return Words(unlisted).items.filter { !$0.isPlaceholder }.map {
            $0.text.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "’", with: "'")
        }
    }

    /// The language of a text when the recogniser is sure of it (≥ 90%), else nil (short, mixed or unclear text).
    private static func clearLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first, probability >= 0.9 else { return nil }
        return language
    }

    /// The word count with each run of number words, and each written number, counted once.
    private static func numbersCollapsed(_ words: [String]) -> Int {
        var count = 0
        var inNumber = false
        for word in words {
            let numeric = NumberWords.isNumeric(word) || word.contains(where: \.isNumber)
            if !numeric || !inNumber { count += 1 }
            inNumber = numeric
        }
        return count
    }

    /// The meant repeats ("had had") in the words.
    private static func doubled(_ words: [String]) -> Set<String> {
        Set(zip(words, words.dropFirst()).filter { $0 == $1 && meantRepeats.contains($0) }.map(\.0))
    }

    /// The word and its crude stems, so "meetings" matches "meeting" and "moved" matches "move".
    static func stems(_ word: String) -> Set<String> {
        var result: Set<String> = [word]
        for suffix in ["'s", "s", "es", "d", "ed", "ing", "ly"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            result.insert(String(word.dropLast(suffix.count)))
        }
        if word.count > 4 && word.hasSuffix("ies") { result.insert(String(word.dropLast(3)) + "y") }
        return result
    }
}

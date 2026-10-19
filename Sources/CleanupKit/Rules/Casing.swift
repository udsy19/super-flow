import Foundation
import SuperFlowCore

/// Capitals, spacing, the per-style finish (behaviour.md §8.4) and joining with the text around the cursor
/// (local-models.md §3.5 step 6).
enum Casing {
    private static let pronounI: [String: String] = ["i": "I", "i'm": "I'm", "i'll": "I'll", "i've": "I've", "i'd": "I'd",
                                                     "i’m": "I’m", "i’ll": "I’ll", "i’ve": "I’ve", "i’d": "I’d"]

    /// Capitalises sentence starts, the pronoun "I" and weekday names (the last two in English only).
    static func sentenceCase(_ words: inout Words, english: Bool) {
        for i in 0..<words.count where !words[i].isPlaceholder {
            let lower = words[i].lower
            if english, let pronoun = pronounI[lower] { words[i].text = pronoun; continue }
            if english, Lexicon.weekdays.contains(lower) { words[i].text = lower.capitalized; continue }
            if words.startsSentence(i) { words[i].text = capitalized(words[i].text) }
        }
    }

    /// "No caps" styles: sentence starts go lower case, except "I", acronyms, mixed-case names and dictionary words.
    static func lowercaseSentenceStarts(_ text: String, keep: Set<String>) -> String {
        var words = Words(text)
        for i in 0..<words.count where !words[i].isPlaceholder && words.startsSentence(i) {
            let word = words[i].text
            guard !keep.contains(word.lowercased()), pronounI[word.lowercased()] == nil, isPlainCapitalized(word) else { continue }
            words[i].text = word.prefix(1).lowercased() + word.dropFirst()
        }
        return words.text
    }

    static func capitalized(_ word: String) -> String {
        guard let first = word.first, first.isLowercase, !word.contains(where: { $0.isUppercase }),
              !word.contains("@"), !word.contains("/"), !word.contains(".") else { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    /// "Hello" but not "HTTP", "iPhone" or "McDonald".
    static func isPlainCapitalized(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        return !word.dropFirst().contains { $0.isUppercase }
    }

    /// Pattern → template, in order: no space before punctuation, single spaces, no spaces around line breaks, and
    /// one mark where passes left two (",." → ".", ".," → "." except after "e.g.", ",," → ",", ".." → ".", "?." → "?").
    private static let tidyRules: [(NSRegularExpression, String)] = [
        // A dot that starts a name stays apart (".venv", ".map").
        (#"[ \t]+([,!?;:…)\]]|\.(?![\p{L}\p{N}]))"#, "$1"),
        (#"[ \t]{2,}"#, " "),
        (#"[ \t]*\n[ \t]*"#, "\n"),
        (#"[,;:]+[ \t]*([.!?])"#, "$1"),
        (#"(?<!\.\p{L})([.!?])[,;:]+"#, "$1"),
        (#",{2,}"#, ","),
        (#"(?<!\.)\.\.(?!\.)"#, "."),
        (#"([!?])\.(?!\.)"#, "$1"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    static func tidy(_ text: String) -> String {
        tidyRules.reduce(text) { text, rule in
            rule.0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rule.1)
        }.trimmingCharacters(in: .whitespaces)
    }
}

/// The finish each writing style asks for (behaviour.md §8.4; the examples in strings.md `personalization_*`).
enum Style {
    /// Style detection (§8.4 "Automatically set messaging style"): how the user already writes in this field, from the
    /// text before the cursor. Needs `detectionMinimumWords` words; nil otherwise. All lower case → very casual;
    /// sentences left without end punctuation → casual; exclamation marks → excited; else formal.
    static let detectionMinimumWords = 8

    static func detect(_ before: String) -> WritingStyle? {
        let text = before.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Dictation.countWords(text) >= detectionMinimumWords else { return nil }
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return nil }
        if !letters.contains(where: \.isUppercase) { return .veryCasual }
        let sentences = text.components(separatedBy: .newlines).flatMap { line in
            line.components(separatedBy: CharacterSet(charactersIn: ".!?")).map { $0.trimmingCharacters(in: .whitespaces) }
        }.filter { Dictation.countWords($0) >= 3 }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let openLines = lines.filter { endsOpen($0) }.count
        let exclamations = text.filter { $0 == "!" }.count
        let periods = text.filter { $0 == "." }.count
        if exclamations >= 1, exclamations * 2 >= periods { return .excited }
        if openLines * 2 >= lines.count, sentences.count <= lines.count + 1 { return .casual }
        return .formal
    }

    /// Applies the style's capitals and end punctuation to finished English text.
    /// `openEnd`: the text ends with a placeholder for a one-line snippet that reads like words ("…to 1 Main St").
    static func apply(_ text: String, style: WritingStyle, category: AppCategory, keep: Set<String>, openEnd: Bool = false,
                      continuing: Bool = false) -> String {
        guard !text.isEmpty else { return text }
        var text = text
        if style == .veryCasual { text = Casing.lowercaseSentenceStarts(text, keep: keep) }
        // A dictation that continues a sentence already in the field does not start a question ("…price, which is…").
        let question = endsWithQuestion(text) && !(continuing && !Words(text).items.dropFirst().contains { Gap.endsSentence($0.gap) })
        let open = openEnd || endsOpen(text)
        let lastIsList = lastLineIsListItem(text)
        switch style {
        case .formal, .excited:
            if open && category != .terminal && !lastIsList {
                text += question ? "?" : style == .excited ? "!" : "."
            } else if style == .excited, endsWithSinglePeriod(text), !question {
                text = String(text.dropLast()) + "!"
            }
        case .casual, .veryCasual:
            if endsWithSinglePeriod(text) { text.removeLast() }
            if open && question && category != .terminal { text += "?" }
        }
        return text
    }

    /// Casual messaging: only proper nouns keep capitals, and no closing period.
    static func casualMessaging(_ text: String, keep: Set<String>) -> String {
        var text = Casing.lowercaseSentenceStarts(text, keep: keep)
        if endsWithSinglePeriod(text) { text.removeLast() }
        return text
    }

    /// Ends in a word, a number or a closing quote/bracket rather than punctuation or a placeholder.
    static func endsOpen(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last.isLetter || last.isNumber || "\"”')%°".contains(last)
    }

    static func endsWithSinglePeriod(_ text: String) -> Bool { text.hasSuffix(".") && !text.hasSuffix("..") }

    static func lastLineIsListItem(_ text: String) -> Bool {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return line.range(of: #"^(?:\d+\.|-) "#, options: .regularExpression) != nil
    }

    /// The last sentence opens like a question ("can you…", "what is…").
    static func endsWithQuestion(_ text: String) -> Bool {
        let words = Words(text)
        guard words.count > 0 else { return false }
        var start = words.sentenceStart(of: words.count - 1)
        // Look past discourse openers ("Also, can you…", "So what's…").
        let openers: Set<String> = ["also", "and", "so", "but", "hey", "ok", "okay", "oh", "well", "then", "um", "plus"]
        while start + 2 < words.count && openers.contains(words[start].lower) { start += 1 }
        let first = words[start].lower
        let second = start + 1 < words.count ? words[start + 1].lower : nil
        return Lexicon.isQuestion(firstWord: first, secondWord: second)
    }
}

/// Fitting the dictation into the text already in the field (local-models.md §3.5 step 6).
enum Joining {
    static func join(_ text: String, before: String, after: String, english: Bool) -> String {
        guard !text.isEmpty else { return text }
        var text = text
        let lastBefore = before.last(where: { !$0.isWhitespace })
        // Continuing a sentence: "…and" + "Then we left" → "…and then we left".
        if english, let lastBefore, !".!?".contains(lastBefore), before.last?.isNewline != true {
            var words = Words(text)
            if words.count > 0, !words[0].isPlaceholder, Lexicon.continuationWords.contains(words[0].lower),
               Casing.isPlainCapitalized(words[0].text), words[0].lower != "i" {
                words[0].text = words[0].text.lowercased()
                text = words.text
            }
        }
        // Inserted mid-sentence: no closing period before a lower-case continuation.
        if let next = after.first(where: { !$0.isWhitespace }), next.isLowercase, Style.endsWithSinglePeriod(text) { text.removeLast() }
        if let last = before.last, !last.isWhitespace, let first = text.first, !",.!?;:…)]}".contains(first), !"([{\"“‘/@#-".contains(last) {
            text = " " + text
        }
        if let next = after.first, next.isLetter || next.isNumber, let last = text.last, !last.isWhitespace { text += " " }
        return text
    }
}

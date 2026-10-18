import Foundation

/// One word of a transcript with the separator text (spaces, punctuation, newlines) that precedes it.
struct Word: Equatable {
    var text: String
    /// What sits between the previous word and this one; the first word's gap is the text's leading separator.
    var gap: String
    /// A snippet placeholder (`⟦S1⟧`): counts as content but no rule ever edits it.
    var isPlaceholder = false

    var lower: String { text.lowercased() }
}

/// A transcript split into words and separators. The rule passes edit this and join it back, so punctuation the
/// speech engine supplied survives every edit that does not touch it.
struct Words {
    var items: [Word]
    /// Separator text after the last word.
    var tail: String

    /// URLs, e-mail addresses, domains and dotted abbreviations stay whole so their dots are never read as sentence
    /// ends; then placeholders, numbers with separators ("3:30", "1,000", "2.5"), and ordinary words with inner
    /// apostrophes and hyphens.
    private static let token = try! NSRegularExpression(pattern: [
        #"(?:https?://|www\.)[^\s<>"]+[^\s<>".,;:!?)]"#,
        #"[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}\-]+(?:\.[\p{L}\p{N}\-]+)+"#,
        #"[\p{L}\p{N}\-]+(?:\.[\p{L}\p{N}\-]+)*\.(?:com|org|net|io|ai|dev|app|co|edu|gov|me|us|uk|de|fr|so)(?![\p{L}\p{N}])"#,
        #"(?:\p{L}\.){2,}"#,
        "⟦[^⟧]*⟧",
        #"\p{N}+(?:[.,:]\p{N}+)+"#,
        #"[\p{L}\p{M}\p{N}](?:[\p{L}\p{M}\p{N}'’\-]*[\p{L}\p{M}\p{N}])?"#,
    ].joined(separator: "|"))

    init(_ text: String) {
        var items: [Word] = []
        let ns = text as NSString
        var cursor = 0
        for match in Words.token.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let gap = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let word = ns.substring(with: match.range)
            items.append(Word(text: word, gap: gap, isPlaceholder: word.hasPrefix("⟦")))
            cursor = match.range.location + match.range.length
        }
        self.items = items
        self.tail = ns.substring(from: cursor)
    }

    var text: String { items.map { $0.gap + $0.text }.joined() + tail }
    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    subscript(_ index: Int) -> Word {
        get { items[index] }
        set { items[index] = newValue }
    }

    /// The separator after word `index`: the next word's gap, or the tail.
    func gap(after index: Int) -> String { index + 1 < items.count ? items[index + 1].gap : tail }

    mutating func setGap(after index: Int, _ gap: String) {
        if index + 1 < items.count { items[index + 1].gap = gap } else { tail = gap }
    }

    /// Removes words and merges the separators around them: a sentence end or newline after the removed words wins,
    /// otherwise the separator before them stays without its pause commas ("so, um, we" → "so we").
    mutating func remove(_ range: Range<Int>) {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= items.count else { return }
        let before = items[range.lowerBound].gap
        let after = gap(after: range.upperBound - 1)
        let atEnd = range.upperBound == items.count
        let merged: String
        switch (range.lowerBound == 0, atEnd) {
        case (true, true): merged = ""
        case (true, false): merged = Gap.trimmed(Gap.withoutCommas(before))
        case (false, true): merged = Gap.isStrong(after) ? Gap.trimmed(after) : Gap.isStrong(before) ? Gap.trimmed(before) : ""
        case (false, false): merged = Gap.isStrong(after) ? after : Gap.withoutCommas(before)
        }
        items.removeSubrange(range)
        if atEnd { tail = merged } else { items[range.lowerBound].gap = merged }
    }

    /// Replaces words with new ones: the first keeps the replaced span's leading gap, the rest are space-separated.
    mutating func replace(_ range: Range<Int>, with words: [String]) {
        guard let first = words.first, range.lowerBound < items.count else { remove(range); return }
        let gap = items[range.lowerBound].gap
        let replacement = [Word(text: first, gap: gap)] + words.dropFirst().map { Word(text: $0, gap: " ") }
        items.replaceSubrange(range, with: replacement)
    }

    /// Whether word `index` starts a sentence: the first word, or one after a sentence end or a line break.
    func startsSentence(_ index: Int) -> Bool { index == 0 || Gap.endsSentence(items[index].gap) }

    /// The index of the first word of the sentence that contains word `index`.
    func sentenceStart(of index: Int) -> Int {
        var i = index
        while i > 0 && !Gap.endsSentence(items[i].gap) { i -= 1 }
        return i
    }
}

/// Reading separators.
enum Gap {
    /// A sentence end (. ! ?, not an ellipsis) or a line break.
    static func endsSentence(_ gap: String) -> Bool {
        if gap.contains(where: \.isNewline) { return true }
        let plain = gap.replacingOccurrences(of: "...", with: "").replacingOccurrences(of: "…", with: "")
        return plain.contains { ".!?".contains($0) }
    }

    /// Punctuation strong enough to keep when the words before it are removed.
    static func isStrong(_ gap: String) -> Bool { endsSentence(gap) || gap.contains { ";:)\"”".contains($0) } }

    static func hasComma(_ gap: String) -> Bool { gap.contains(",") }

    /// Only spaces (the words are adjacent in speech).
    static func isSpace(_ gap: String) -> Bool { !gap.isEmpty && gap.allSatisfy { $0 == " " } }

    static func withoutCommas(_ gap: String) -> String {
        let stripped = gap.replacingOccurrences(of: ",", with: "")
        if stripped.contains(where: \.isNewline) { return stripped.trimmingCharacters(in: .whitespaces) }
        let collapsed = stripped.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespaces).isEmpty ? " " : collapsed
    }

    static func trimmed(_ gap: String) -> String { gap.trimmingCharacters(in: .whitespaces) }
}

/// Small closed word classes several passes share.
enum Lexicon {
    static let determiners: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "your", "our", "their", "his", "her", "its", "each", "every",
        "any", "some", "no", "one", "another", "which", "what", "whose",
    ]
    static let prepositions: Set<String> = [
        "at", "in", "on", "to", "for", "from", "with", "by", "about", "before", "after", "until", "till", "around", "into", "onto",
        "via", "near", "since", "during",
    ]
    static let subjectPronouns: Set<String> = ["i", "you", "we", "they", "he", "she", "it", "i'm", "i'll", "we'll", "let's"]
    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                         "november", "december"]
    static let timeWords: Set<String> = ["today", "tomorrow", "tonight", "yesterday", "noon", "midnight", "morning", "afternoon",
                                         "evening", "am", "pm", "a.m.", "p.m."]
    /// Auxiliaries that open a yes/no question.
    static let questionOpeners: Set<String> = [
        "can", "could", "would", "will", "should", "shall", "may", "might", "do", "does", "did", "is", "are", "was", "were", "am",
        "have", "has", "had", "isn't", "aren't", "don't", "doesn't", "didn't", "won't", "wouldn't", "can't", "couldn't", "shouldn't",
    ]
    static let questionWords: Set<String> = ["what", "why", "how", "when", "where", "who", "which", "whose", "whom"]

    /// Words that may be written in lower case when a dictation continues a sentence already in the text field.
    static let continuationWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "so", "then", "also", "because", "if", "when", "while", "which", "that", "this",
        "these", "those", "it", "it's", "we", "we're", "we'll", "you", "you're", "they", "they're", "he", "she", "there", "here",
        "to", "for", "with", "of", "in", "on", "at", "by", "from", "as", "not", "just", "maybe", "probably", "really", "very",
        "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "can", "could",
        "should", "my", "your", "our", "their", "his", "her", "its", "all", "some", "any", "more", "most", "other", "about",
        "into", "over", "after", "before", "until", "since", "though", "although", "plus", "too", "even", "still", "yet",
        "what", "how", "why", "where", "who", "like", "let's", "please", "thanks", "thank", "okay", "ok", "yes", "yeah", "no",
    ]

    /// What can follow an auxiliary in a question ("can you", "is the", "will it").
    private static let questionSubjects: Set<String> = [
        "i", "you", "we", "they", "he", "she", "it", "there", "this", "that", "these", "those", "the", "a", "an", "my", "your", "our",
        "their", "his", "her", "its", "anyone", "anybody", "someone", "somebody", "everyone", "everybody", "any", "all", "u", "ya",
    ]

    /// Whether a sentence opening with these words is a question: an auxiliary before its subject ("can you…", "is the
    /// room…", "don't you…" but not "don't do that" or "do it now"), or a question word before an auxiliary ("what is…").
    static func isQuestion(firstWord: String, secondWord: String?) -> Bool {
        guard let second = secondWord else { return false }
        if questionOpeners.contains(firstWord) {
            if firstWord == "do" && ["it", "this", "that"].contains(second) { return false }
            return questionSubjects.contains(second)
        }
        guard questionWords.contains(firstWord) else { return false }
        return questionOpeners.contains(second) || ["'s", "’s"].contains { second.hasSuffix($0) }
            || ["about", "if", "else", "much", "many", "long", "often", "come"].contains(second)
    }
}

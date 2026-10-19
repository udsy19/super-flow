import Foundation
import SuperFlowCore

/// The personal dictionary and snippets (behaviour.md §8.5, §8.6; local-models.md §3.5 steps 2–5).
///
/// - Replacements ("misspelling → spelling", including learned corrections) are applied before the LLM.
/// - Sound-alikes of dictionary words become the words before it ("Shivon" → "Siobhan", `SoundAlikes`).
/// - Spellings are enforced after it, case-exact, and tolerate the spacing and accents speech engines drop
///   ("chat gpt" → "ChatGPT", "Anais" → "Anaïs").
/// - Snippet triggers become opaque placeholders (`⟦S1⟧`) before the LLM and are expanded verbatim at the very end.
struct Vocabulary {
    private struct Rule { var pattern: NSRegularExpression; var output: String; var snippetID: UUID? = nil }

    private let replacements: [Rule]
    private let spellings: [Rule]
    private let snippets: [Rule]
    /// Lower-cased dictionary words that carry capitals; casual styles never lower-case them.
    let keepCase: Set<String>
    /// Dictionary words for the LLM's `<dictionary>` block: starred first (behaviour.md §6.6), at most 50.
    let hints: [String]
    let soundAlikes: SoundAlikes

    init(dictionary: [DictionaryEntry], snippets: [Snippet]) {
        let byLength: (String, String) -> Bool = { $0.count > $1.count }
        replacements = dictionary.compactMap { entry in
            guard let target = entry.replacement?.trimmingCharacters(in: .whitespaces), !target.isEmpty,
                  let pattern = Vocabulary.pattern(entry.phrase) else { return nil }
            return Rule(pattern: pattern, output: target)
        }.sorted { byLength($0.pattern.pattern, $1.pattern.pattern) }

        let spelled = dictionary.map { ($0.replacement?.isEmpty == false ? $0.replacement! : $0.phrase).trimmingCharacters(in: .whitespaces) }
        let distinct = Array(Set(spelled.filter { !$0.isEmpty })).sorted(by: byLength)
        spellings = distinct.compactMap { word in
            // An all-lower-case word adds nothing to enforce unless it carries accents ("café").
            guard word != word.lowercased() || word != word.folding(options: .diacriticInsensitive, locale: nil),
                  let pattern = Vocabulary.pattern(word, flexible: true) else { return nil }
            return Rule(pattern: pattern, output: word)
        }
        keepCase = Set(distinct.filter { $0 != $0.lowercased() }.flatMap { $0.lowercased().split(separator: " ").map(String.init) })
        soundAlikes = SoundAlikes(spellings: distinct)

        let ordered = dictionary.filter(\.isStarred) + dictionary.filter { !$0.isStarred }
        hints = Array(NSOrderedSet(array: ordered.map { $0.replacement?.isEmpty == false ? $0.replacement! : $0.phrase })
            .compactMap { $0 as? String }.prefix(50))

        self.snippets = snippets.compactMap { snippet in
            let words = snippet.trigger.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
            guard !words.isEmpty, !snippet.expansion.isEmpty else { return nil }
            let body = words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"[\s\p{P}]+"#)
            guard let pattern = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])"# + body + #"(?![\p{L}\p{N}])"#,
                                                         options: [.caseInsensitive]) else { return nil }
            return Rule(pattern: pattern, output: snippet.expansion, snippetID: snippet.id)
        }.sorted { byLength($0.pattern.pattern, $1.pattern.pattern) }
    }

    // MARK: Snippets

    /// Swaps each spoken trigger for a placeholder; returns the text, what each placeholder expands to, and the
    /// snippets used (each once, in order of first use).
    func insertPlaceholders(_ text: String) -> (text: String, expansions: [String: String], snippets: [UUID]) {
        var text = text
        var expansions: [String: String] = [:]
        var used: [UUID] = []
        for rule in snippets {
            let matches = rule.pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let token = "⟦S\(expansions.count + 1)⟧"
                expansions[token] = rule.output
                text.replaceSubrange(range, with: token)
            }
            if !matches.isEmpty, let id = rule.snippetID, !used.contains(id) { used.append(id) }
        }
        return (text, expansions, used)
    }

    static func expand(_ text: String, _ expansions: [String: String]) -> String {
        expansions.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    // MARK: Dictionary

    func applyReplacements(_ text: String) -> String { apply(replacements, to: text, matchCase: false) }

    func enforceSpellings(_ text: String) -> String { apply(spellings, to: text, matchCase: true) }

    private func apply(_ rules: [Rule], to text: String, matchCase: Bool) -> String {
        rules.reduce(text) { text, rule in
            let ns = text as NSString
            var result = text
            for match in rule.pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                var output = rule.output
                // "café" at a sentence start stays capitalised.
                if matchCase, output == output.lowercased(), result[range].first?.isUppercase == true {
                    output = output.prefix(1).uppercased() + output.dropFirst()
                }
                result.replaceSubrange(range, with: output)
            }
            return result
        }
    }

    /// A whole-word, case-insensitive pattern for a phrase. Accented letters also match their plain form; with
    /// `flexible`, the phrase's words and its camel-case or letter/digit parts may be joined or split by spaces or
    /// hyphens ("ChatGPT" matches "chat gpt", "Hugging Face" matches "hugging-face").
    static func pattern(_ phrase: String, flexible: Bool = false) -> NSRegularExpression? {
        let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let body = words.map { word in
            let parts = flexible ? segments(word) : [word]
            return parts.map { $0.map(character).joined() }.joined(separator: #"[\s\-]?"#)
        }.joined(separator: flexible ? #"[\s\-]*"# : #"\s+"#)
        return try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])"# + body + #"(?![\p{L}\p{N}])"#, options: [.caseInsensitive])
    }

    private static func character(_ c: Character) -> String {
        let plain = String(c).folding(options: .diacriticInsensitive, locale: nil)
        let escaped = NSRegularExpression.escapedPattern(for: String(c))
        guard plain != String(c), plain.count == 1 else { return escaped }
        return "[" + escaped + NSRegularExpression.escapedPattern(for: plain) + "]"
    }

    /// "ChatGPT" → ["Chat", "GPT"], "iPhone" → ["i", "Phone"], "GPT4" → ["GPT", "4"].
    private static func segments(_ word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for c in word {
            if let p = previous {
                let caseBreak = p.isLowercase && c.isUppercase
                let digitBreak = p.isNumber != c.isNumber && (p.isLetter || p.isNumber) && (c.isLetter || c.isNumber)
                if caseBreak || digitBreak { parts.append(current); current = "" }
            }
            current.append(c)
            previous = c
        }
        parts.append(current)
        return parts
    }
}

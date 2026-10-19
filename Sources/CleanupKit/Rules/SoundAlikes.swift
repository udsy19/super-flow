import Foundation
import SuperFlowCore

/// Dictionary words the speech engine heard as something that sounds the same (cleanup-quality.md §5 P2.10): "Shivon"
/// → Siobhan, "Eefa" → Aoife, "cube control" → kubectl, "postgres QL" → PostgreSQL. Runs before the model, which
/// rarely makes these jumps on its own (the 2 B model got 3 of 15 wrong).
///
/// Matching is deliberately narrow, because a wrong swap is worse than a missed one:
/// - one heard word must be a capitalised name mid-sentence, at least four letters, that sounds the same as the entry
///   (one sound apart at most, for longer names);
/// - two or three heard words must spell the entry's letters exactly, or sound like a one-word entry while holding
///   no article, preposition or pronoun.
struct SoundAlikes {
    private struct Entry {
        var spelling: String
        /// Lower-case letters and digits only.
        var letters: String
        var key: String
        var isOneWord: Bool
    }

    private let entries: [Entry]

    init(spellings: [String]) {
        entries = spellings.compactMap { spelling in
            let letters = Self.letters(spelling)
            guard letters.filter(\.isLetter).count >= 4 else { return nil }
            return Entry(spelling: spelling, letters: letters, key: Self.key(spelling), isOneWord: !spelling.contains(" "))
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Words a sound-alike window may not contain: they glue ordinary phrases together ("a course" is not "OKRs").
    private static let glue = Lexicon.determiners.union(Lexicon.prepositions).union(Lexicon.subjectPronouns)

    func apply(_ words: inout Words) {
        guard !entries.isEmpty else { return }
        var i = 0
        while i < words.count {
            if let (length, spelling) = match(words, at: i) {
                let gap = words[i].gap
                words.items.replaceSubrange(i..<i + length, with: [Word(text: spelling, gap: gap)])
            }
            i += 1
        }
    }

    /// The longest window starting at `index` that sounds like an entry, and the entry's spelling.
    private func match(_ words: Words, at index: Int) -> (Int, String)? {
        for length in stride(from: 3, through: 1, by: -1) where index + length <= words.count {
            let window = Array(words.items[index..<index + length])
            guard !window.contains(where: \.isPlaceholder),
                  window.dropFirst().allSatisfy({ Gap.isSpace($0.gap) }) else { continue }
            let heard = window.map(\.text).joined(separator: " ")
            let letters = Self.letters(heard)
            if entries.contains(where: { $0.letters == letters && $0.spelling == heard }) { return nil }
            if length == 1 {
                guard let first = heard.first, first.isUppercase, !words.startsSentence(index), heard.filter(\.isLetter).count >= 4 else { continue }
                let key = Self.key(heard)
                if let entry = entries.first(where: { $0.letters != letters && Self.soundsAlike(key, $0.key, allowance: $0.key.count > 3 ? 1 : 0) }) {
                    return (1, entry.spelling)
                }
                continue
            }
            if let entry = entries.first(where: { $0.letters == letters }) { return (length, entry.spelling) }
            let lowered = window.map(\.lower)
            let key = Self.key(heard)
            let exact = entries.first { $0.isOneWord && $0.key.count >= 4 && $0.key == key }
            if let entry = exact, !lowered.contains(where: Self.glue.contains) { return (length, entry.spelling) }
            guard !lowered.contains(where: { Self.glue.contains($0) || Lexicon.continuationWords.contains($0) }) else { continue }
            if let entry = entries.first(where: { $0.isOneWord && $0.key.count >= 5 && key.prefix(2) == $0.key.prefix(2)
                && Self.soundsAlike(key, $0.key, allowance: 2) }) {
                return (length, entry.spelling)
            }
        }
        return nil
    }

    private static func soundsAlike(_ a: String, _ b: String, allowance: Int) -> Bool {
        a.first == b.first && abs(a.count - b.count) <= allowance && TextDistance.edits(a, b) <= allowance
    }

    static func letters(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    /// A rough English sound key in the spirit of Metaphone: consonant sounds only, voiced and voiceless pairs merged, a
    /// leading vowel as "A", doubled sounds once. Irish "bh"/"mh" read as "v" ("Siobhan" and "Shivon" both give XFN).
    static func key(_ text: String) -> String {
        let s = Array(letters(text).filter(\.isLetter))
        guard !s.isEmpty else { return "" }
        func at(_ i: Int) -> Character? { i >= 0 && i < s.count ? s[i] : nil }
        func isVowel(_ c: Character?) -> Bool { c.map { "aeiou".contains($0) } ?? false }
        func soft(_ c: Character?) -> Bool { c.map { "eiy".contains($0) } ?? false }
        var key: [Character] = []
        var i = 0
        if s.count > 1, ["kn", "gn", "pn", "wr", "ps"].contains(String(s[0...1])) { i = 1 }
        else if isVowel(s[0]) || ("wy".contains(s[0]) && isVowel(at(1))) { key = ["A"]; i = 1 }
        while i < s.count {
            let next = at(i + 1), after = at(i + 2)
            var sound = ""
            var step = 1
            switch s[i] {
            case "b": if next == "h" { sound = "F"; step = 2 } else { sound = "P" }
            case "c":
                if next == "h" { sound = after == "r" || (i == 0 && !isVowel(after)) ? "K" : "X"; step = 2 }
                else if next == "k" || next == "q" { sound = "K"; step = 2 }
                else { sound = soft(next) ? "S" : "K" }
            case "d": if next == "g", soft(after) { sound = "J"; step = 2 } else { sound = "T" }
            case "f", "v": sound = "F"
            case "g":
                if next == "h" { sound = i == 0 ? "K" : ""; step = 2 }
                else if next == "n", i + 2 == s.count { sound = "" }
                else { sound = soft(next) ? "J" : "K" }
            case "j": sound = "J"
            case "k", "q": sound = "K"
            case "l": sound = "L"
            case "m": if next == "h" { sound = "F"; step = 2 } else { sound = "M" }
            case "n": sound = "N"
            case "p": if next == "h" { sound = "F"; step = 2 } else { sound = "P" }
            case "r": sound = "R"
            case "s":
                if next == "h" { sound = "X"; step = 2 }
                else if next == "c", after == "h" { sound = "SK"; step = 3 }
                else if next == "i", after == "o" || after == "a" { sound = "X"; step = 2 }
                else { sound = "S" }
            case "t":
                if next == "h" { sound = "0"; step = 2 }
                else if next == "i", after == "o" || after == "a" { sound = "X"; step = 2 }
                else if next == "c", after == "h" { sound = "" }
                else { sound = "T" }
            case "x": sound = "KS"
            case "z": sound = "S"
            default: sound = ""   // vowels, h, w, y
            }
            for c in sound where key.last != c { key.append(c) }
            i += step
        }
        return String(key)
    }
}

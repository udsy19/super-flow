import Foundation
import SuperFlowCore

/// Auto-add to dictionary (behaviour.md §8.5, §9.4): after an insertion, the words the user changed the inserted text
/// into become dictionary entries. A word swapped for another one that looks like a correction of it (close spelling,
/// or the same letters with capitals or accents) becomes a replacement rule "heard → written"; a capitalised word the
/// user typed in that was not there becomes a plain entry. Everyday words and punctuation-only changes are ignored.
public enum AutoLearn {
    public static let maxEntries = 5

    /// Entries to add for `edited`, the field's version of `cleaned`; `known` phrases are skipped.
    public static func entries(cleaned: String, edited: String, known: [DictionaryEntry]) -> [DictionaryEntry] {
        let before = tokens(cleaned), after = tokens(edited)
        guard !before.isEmpty, !after.isEmpty, before != after else { return [] }
        let knownPhrases = Set(known.flatMap { [$0.phrase.lowercased(), $0.replacement?.lowercased() ?? ""] })
        var entries: [DictionaryEntry] = []
        var seen: Set<String> = []
        func add(_ entry: DictionaryEntry) {
            let key = entry.phrase.lowercased()
            guard !knownPhrases.contains(key), !knownPhrases.contains(entry.replacement?.lowercased() ?? "\u{0}"), seen.insert(key).inserted,
                  entries.count < maxEntries else { return }
            entries.append(entry)
        }
        for change in diff(before, after) {
            switch change {
            case .substitution(let heard, let written):
                guard isWord(heard), isWord(written), heard.lowercased() != written.lowercased() || heard != written else { continue }
                if looksLikeCorrection(heard: heard, written: written) {
                    add(DictionaryEntry(phrase: heard, replacement: written, source: .learned))
                }
            case .insertion(let written):
                guard isWord(written), isProperNoun(written) else { continue }
                add(DictionaryEntry(phrase: written, source: .learned))
            }
        }
        return entries
    }

    public enum Change: Equatable {
        case substitution(heard: String, written: String)
        case insertion(written: String)
    }

    /// Word-level diff by longest common subsequence; equal-length runs of removed and added words pair up as substitutions.
    public static func diff(_ a: [String], _ b: [String]) -> [Change] {
        let n = a.count, m = b.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var changes: [Change] = []
        var removed: [String] = [], added: [String] = []
        func flush() {
            if removed.count == added.count {
                for (heard, written) in zip(removed, added) { changes.append(.substitution(heard: heard, written: written)) }
            } else if removed.isEmpty {
                added.forEach { changes.append(.insertion(written: $0)) }
            }
            removed = []; added = []
        }
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] { flush(); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { removed.append(a[i]); i += 1 }
            else { added.append(b[j]); j += 1 }
        }
        removed += a[i...]
        added += b[j...]
        flush()
        return changes
    }

    static func tokens(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }.map { String($0).trimmingCharacters(in: trim) }.filter { !$0.isEmpty }
    }

    private static let trim = CharacterSet.punctuationCharacters.union(.symbols).subtracting(CharacterSet(charactersIn: "'’-"))

    static func isWord(_ token: String) -> Bool {
        token.count >= 2 && token.contains(where: \.isLetter) && !common.contains(token.lowercased())
    }

    /// Capitals past the first letter, or a first capital on a word that is not an everyday one.
    static func isProperNoun(_ token: String) -> Bool {
        guard let first = token.first, first.isUppercase else { return false }
        return token.dropFirst().contains(where: \.isUppercase) || token.count >= 3
    }

    /// The same word with different capitals or accents, or a spelling within a short edit distance (a quarter of the
    /// length, at least one, at most three).
    static func looksLikeCorrection(heard: String, written: String) -> Bool {
        let plainHeard = heard.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let plainWritten = written.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if plainHeard == plainWritten { return heard != written }
        let distance = editDistance(plainHeard, plainWritten)
        return distance <= min(3, max(1, max(heard.count, written.count) / 4))
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var previous = Array(0...y.count)
        for i in 1...max(1, x.count) where i <= x.count {
            var current = [i] + [Int](repeating: 0, count: y.count)
            for j in 1...max(1, y.count) where j <= y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[y.count]
    }

    /// Words a correction never targets.
    static let common: Set<String> = [
        "the", "and", "for", "that", "this", "with", "you", "your", "are", "was", "were", "have", "has", "had", "not", "but", "can",
        "will", "would", "should", "could", "from", "into", "about", "just", "some", "what", "when", "where", "which", "who", "how",
        "our", "they", "them", "their", "there", "then", "than", "its", "it's", "i'm", "i'll", "i've", "we're", "don't", "doesn't",
        "yes", "yeah", "okay", "ok", "please", "thanks", "thank", "hi", "hey", "hello", "bye", "also", "very", "really", "like",
    ]
}

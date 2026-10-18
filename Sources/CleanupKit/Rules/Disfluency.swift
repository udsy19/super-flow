import Foundation

/// Fillers and stutters (local-models.md §3.5 rules-only fallback).
enum Disfluency {
    /// Hesitation sounds, removed wherever they stand.
    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "ahh", "hmm", "hmmm", "mm", "mmm"]
    /// Discourse fillers, removed only when set off by commas ("it was, like, great"), because "I like it" and
    /// "you know the answer" are real words.
    static let commaFillers: [[String]] = [["you", "know"], ["i", "mean"], ["like"]]
    /// Words whose doubling is usually meant ("had had", "that that", "bye bye", "very very").
    static let meantRepeats: Set<String> = [
        "had", "that", "is", "do", "bye", "no", "yes", "yeah", "ha", "haha", "knock", "very", "really", "so", "now", "there", "well",
        "tsk", "la", "go",
    ]

    static func removeFillers(_ words: inout Words) {
        var i = words.count - 1
        while i >= 0 {
            if !words[i].isPlaceholder, fillers.contains(words[i].lower) { words.remove(i..<i + 1) }
            i -= 1
        }
        i = words.count - 1
        while i >= 0 {
            for phrase in commaFillers where matches(phrase, in: words, at: i) {
                let end = i + phrase.count
                let before = words[i].gap
                let after = words.gap(after: end - 1)
                let openedByPause = i == 0 || Gap.hasComma(before) || Gap.endsSentence(before)
                let closedByPause = Gap.hasComma(after) || (Gap.hasComma(before) && (Gap.endsSentence(after) || end == words.count))
                if openedByPause && closedByPause {
                    words.remove(i..<end)
                    break
                }
            }
            i -= 1
        }
    }

    /// "the the" → "the", "I, I think" → "I think", "I think I think we" → "I think we". Never across a sentence end,
    /// never for numbers (digits read out one by one) and never for the doublings people mean.
    static func collapseRepeats(_ words: inout Words) {
        for n in [3, 2, 1] {
            var i = 0
            while i + 2 * n <= words.count {
                if isRepeat(words, at: i, length: n) { words.remove(i + n..<i + 2 * n) } else { i += 1 }
            }
        }
    }

    private static func isRepeat(_ words: Words, at i: Int, length n: Int) -> Bool {
        for k in 0..<n {
            let a = words[i + k], b = words[i + n + k]
            if a.isPlaceholder || a.lower != b.lower || NumberWords.isNumeric(a.lower) { return false }
        }
        if n == 1 && meantRepeats.contains(words[i].lower) { return false }
        return (i + 1..<i + 2 * n).allSatisfy { !Gap.endsSentence(words[$0].gap) }
    }

    static func matches(_ phrase: [String], in words: Words, at i: Int) -> Bool {
        guard i + phrase.count <= words.count else { return false }
        for (k, part) in phrase.enumerated() {
            if words[i + k].lower != part { return false }
            if k > 0 && !Gap.isSpace(words[i + k].gap) { return false }
        }
        return true
    }
}

import Foundation

/// Explicit backtracking (behaviour.md §8.3, local-models.md §3.7 conclusion 2). Small models miss these, so the
/// rules resolve them before the LLM sees the text.
enum SelfCorrections {
    /// Drop the sentence (or clause) before the marker: "Let's meet Tuesday. Scratch that. Wednesday works."
    static let retractions: [[String]] = [["scratch", "that"], ["strike", "that"], ["delete", "that"]]
    /// The same, but only when the marker stands alone between pauses ("never mind the details" is not a retraction).
    static let pausedRetractions: [[String]] = [["never", "mind"], ["forget", "that"], ["cancel", "that"]]
    /// "A <marker> B": B replaces the end of A. Strong markers are unambiguous corrections.
    static let strongMarkers: [[String]] = [
        ["no", "wait"], ["wait", "no"], ["actually", "no"], ["no", "actually"], ["or", "rather"], ["sorry", "no"], ["oops"],
        ["make", "that"], ["i", "meant"], ["no", "sorry"],
    ]
    /// Ordinary words that also mark corrections; they apply only when B parallels the end of A (same word or same
    /// kind: numbers, days, months, times, names), so "I actually like it" and "I mean it" are left alone.
    static let weakMarkers: [[String]] = [["i", "mean"], ["actually"], ["sorry"], ["no"]]
    private static let interjections: Set<String> = ["actually", "oh", "wait", "no", "sorry", "okay", "ok", "well", "so", "hmm"]

    static func apply(_ words: inout Words) {
        // Each applied correction shortens the text, so this terminates; the cap is a guard against pathological input.
        for _ in 0..<32 {
            guard let step = nextCorrection(in: words) else { return }
            step(&words)
        }
    }

    private typealias Step = (inout Words) -> Void

    private static func nextCorrection(in words: Words) -> Step? {
        for m in 0..<words.count where !words[m].isPlaceholder {
            if let marker = retractions.first(where: { Disfluency.matches($0, in: words, at: m) }) {
                return { retract(&$0, marker: m, length: marker.count) }
            }
            if let marker = pausedRetractions.first(where: { Disfluency.matches($0, in: words, at: m) }) {
                let after = words.gap(after: m + marker.count - 1)
                let standsAlone = m + marker.count == words.count || Gap.hasComma(after) || Gap.endsSentence(after)
                if standsAlone { return { retract(&$0, marker: m, length: marker.count) } }
            }
            for (markers, strong) in [(strongMarkers, true), (weakMarkers, false)] {
                for marker in markers where matchesMarker(marker, in: words, at: m) {
                    if let step = replacement(in: words, marker: m, length: marker.count, strong: strong) { return step }
                }
            }
        }
        return nil
    }

    /// Removes the marker and the sentence before it (or, mid-sentence, the clause since the last sentence end).
    private static func retract(_ words: inout Words, marker m: Int, length: Int) {
        guard m > 0 else { words.remove(0..<length); return }
        var start = words.sentenceStart(of: m - 1)
        // Mid-sentence ("…on Tuesday, and we were going to do payments on Wednesday, but scratch that, we're
        // holding payments"), only the clause before the marker goes, not the facts before it.
        if !Gap.endsSentence(words[m].gap), m - 1 > start {
            var clauses = (start + 1..<m).filter { Gap.hasComma(words[$0].gap) }
            let filler: Set<String> = ["but", "and", "so", "or", "actually", "oh", "no", "wait", "well", "okay", "ok"]
            while let last = clauses.last, (last..<m).allSatisfy({ filler.contains(words[$0].lower) }) { clauses.removeLast() }
            if let clause = clauses.last {
                let leading = words[clause].gap
                words.items.removeSubrange(clause..<m + length)
                if clause < words.count { words[clause].gap = Gap.withoutCommas(leading) == " " ? ", " : leading } else { words.tail = "" }
                return
            }
        }
        // "I'll be there at 5. Actually, scratch that." retracts the previous sentence, not just "Actually".
        if start > 0 && (start..<m).allSatisfy({ interjections.contains(words[$0].lower) }) { start = words.sentenceStart(of: start - 1) }
        let leading = words[start].gap
        words.remove(start..<m + length)
        if start < words.count { words[start].gap = start == 0 ? Gap.trimmed(Gap.withoutCommas(leading)) : leading }
        else { words.tail = start == 0 ? "" : Gap.trimmed(leading) }
    }

    /// Marker words may be separated by the commas speech engines write ("No, wait, four").
    static func matchesMarker(_ phrase: [String], in words: Words, at i: Int) -> Bool {
        guard i + phrase.count <= words.count else { return false }
        for (k, part) in phrase.enumerated() {
            if words[i + k].lower != part { return false }
            if k > 0 && Gap.endsSentence(words[i + k].gap) { return false }
        }
        return true
    }

    private static func replacement(in words: Words, marker m: Int, length: Int, strong: Bool) -> Step? {
        guard m > 0 else { return nil }
        // A runs back to its sentence start; a strong marker may follow a sentence end the speech engine inserted
        // ("…at three. No wait, four.").
        let markerGap = words[m].gap
        if Gap.endsSentence(markerGap) && !strong { return nil }
        // Interjections right before a strong marker belong to it ("five, actually, make that six").
        var a = m
        if strong {
            while a - 1 > 0 && interjections.contains(words[a - 1].lower) && !Gap.endsSentence(words[a].gap) { a -= 1 }
        }
        let aStart = words.sentenceStart(of: a - 1)
        let bStart = m + length
        guard bStart < words.count else { return nil }
        var bEnd = bStart + 1
        while bEnd < words.count && !isClauseBreak(words[bEnd].gap) { bEnd += 1 }
        let bLength = bEnd - bStart
        guard bLength <= 6, !words[bStart].isPlaceholder else { return nil }

        let b0 = words[bStart].lower
        let window = max(aStart, a - 8)..<a
        var from: Int?
        if let anchor = window.reversed().first(where: { words[$0].lower == b0 }) {
            // Weak markers need a short B, or an anchor close to the marker, or a restart on a content word
            // ("…to accounting, actually send it to Dana").
            let close = a - anchor <= 4
            let content = !Lexicon.continuationWords.contains(b0) && !Lexicon.prepositions.contains(b0)
            if strong || bLength <= 3 || close || content { from = anchor }
        } else if words[bEnd - 1].lower == words[a - 1].lower, a - bLength >= aStart, bLength >= 2 {
            // Parallel endings ("fifteen percent, or rather sixteen percent"): B replaces as many words of A.
            from = a - bLength
        } else if bLength <= (strong ? 6 : 3), let kind = Kind(words[bStart].text, sentenceStart: words.startsSentence(bStart)),
                  Kind(words[a - 1].text, sentenceStart: a - 1 == aStart) == kind {
            var j = a - 1
            while j - 1 >= aStart && Kind(words[j - 1].text, sentenceStart: j - 1 == aStart) == kind && Gap.isSpace(words[j].gap) { j -= 1 }
            from = j
        } else if strong {
            from = softAnchor(words, b0: b0, window: window) ?? a - 1
        }
        guard let start = from else { return nil }
        return { words in
            let leading = words[start].gap
            let replacement = (bStart..<bEnd).map { words[$0].text }
            let gaps = (bStart..<bEnd).map { $0 == bStart ? leading : words[$0].gap }
            words.items.replaceSubrange(start..<bEnd, with: zip(replacement, gaps).map { Word(text: $0, gap: $1) })
        }
    }

    /// B ends at a comma, sentence end or line break.
    private static func isClauseBreak(_ gap: String) -> Bool { Gap.endsSentence(gap) || gap.contains { ",;:".contains($0) } }

    /// For strong markers: B opening with a preposition, determiner or pronoun replaces A from its last word of that class.
    private static func softAnchor(_ words: Words, b0: String, window: Range<Int>) -> Int? {
        for wordClass in [Lexicon.prepositions, Lexicon.determiners, Lexicon.subjectPronouns] where wordClass.contains(b0) {
            return window.reversed().first { wordClass.contains(words[$0].lower) }
        }
        return nil
    }

    /// The kinds of words a correction swaps one for another.
    private enum Kind: Equatable {
        case number, weekday, month, time, name, code

        init?(_ word: String, sentenceStart: Bool) {
            let lower = word.lowercased()
            if NumberWords.isNumeric(lower) { self = .number }
            // "v2", "Q3", "iOS17": letters with digits.
            else if lower.contains(where: \.isNumber) && lower.contains(where: \.isLetter) { self = .code }
            else if Lexicon.weekdays.contains(lower) { self = .weekday }
            else if Lexicon.months.contains(lower) && lower != "may" { self = .month }
            else if Lexicon.timeWords.contains(lower) { self = .time }
            // A capital at a sentence start says nothing ("Tell Mark, I mean Mike").
            else if let first = word.first, first.isUppercase, lower != "i", !sentenceStart { self = .name }
            else { return nil }
        }
    }
}

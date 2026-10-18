import Foundation

/// Spoken enumerations become a numbered list (behaviour.md §8.3): "my goals are first ship the app second write
/// the docs and third rest" → "my goals are:\n1. ship the app\n2. write the docs\n3. rest" (casing comes later).
enum Lists {
    /// Ordinal markers by position: "first"/"firstly", "number one", "step one"; "finally"/"lastly" close a list of 2+.
    private static let ordinals = [
        ["first", "firstly"], ["second", "secondly"], ["third", "thirdly"], ["fourth", "fourthly"], ["fifth", "fifthly"],
        ["sixth"], ["seventh"], ["eighth"], ["ninth"], ["tenth"],
    ]
    private static let cardinals = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    private static let closers: Set<String> = ["finally", "lastly"]
    /// A word before an ordinal that makes it part of a phrase ("the first time", "a second", "twenty first").
    private static let blockers: Set<String> = Lexicon.determiners.union([
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "at", "in", "for", "come", "came",
        "was", "were", "is", "be", "it's", "place", "finish", "finished",
    ])

    private struct Marker { var index: Int; var length: Int }

    static func apply(_ words: inout Words) {
        guard let markers = findMarkers(words) else { return }
        // Rebuild back to front so indices stay valid: each marker's words go, and the next word starts the item.
        for (n, marker) in markers.enumerated().reversed() {
            var start = marker.index
            // "…the app and second…": the "and" before a marker belongs to the list syntax.
            if n > 0, start > 0, ["and", "then"].contains(words[start - 1].lower) { start -= 1 }
            let itemStart = marker.index + marker.length
            let intro = n == 0 && start > 0
            let prefix = n == 0 && start == 0 ? "" : intro ? ":\n" : "\n"
            words.items.removeSubrange(start..<itemStart)
            // "first of all".
            if Disfluency.matches(["of", "all"], in: words, at: start) { words.items.removeSubrange(start..<start + 2) }
            guard start < words.count else { return }
            words[start].gap = prefix + "\(n + 1). "
        }
        // No closing period on the last item; a following sentence keeps its own.
        if words.tail.allSatisfy({ ".,; ".contains($0) }) { words.tail = "" }
    }

    private static func findMarkers(_ words: Words) -> [Marker]? {
        var markers: [Marker] = []
        var i = 0
        while i < words.count {
            let expected = markers.count
            if let length = marker(words, at: i, position: expected) {
                markers.append(Marker(index: i, length: length))
                i += length
                continue
            }
            if markers.count >= 2, closers.contains(words[i].lower), isClauseStart(words, at: i) {
                markers.append(Marker(index: i, length: 1))
                break
            }
            i += 1
        }
        // Items need content between markers.
        guard markers.count >= 2, zip(markers, markers.dropFirst()).allSatisfy({ $0.index + $0.length < $1.index }),
              let last = markers.last, last.index + last.length < words.count else { return nil }
        return markers
    }

    /// Whether an ordinal marker for list position `position` (0-based) starts at `i`; returns its word count.
    private static func marker(_ words: Words, at i: Int, position: Int) -> Int? {
        guard position < ordinals.count, isClauseStart(words, at: i) else { return nil }
        let lower = words[i].lower
        if ordinals[position].contains(lower) { return 1 }
        if ["number", "step"].contains(lower), i + 1 < words.count, words[i + 1].lower == cardinals[position], Gap.isSpace(words[i + 1].gap) {
            return 2
        }
        return nil
    }

    private static func isClauseStart(_ words: Words, at i: Int) -> Bool {
        if i == 0 || Gap.endsSentence(words[i].gap) || words[i].gap.contains(where: { ",;:".contains($0) }) { return true }
        return !blockers.contains(words[i - 1].lower)
    }
}

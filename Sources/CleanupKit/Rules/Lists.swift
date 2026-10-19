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

    /// Phrases that introduce a to-do or shopping list ("we need to …", "todo for tomorrow …").
    private static let introducers: [[String]] = [
        ["need", "to"], ["needs", "to"], ["have", "to"], ["has", "to"], ["got", "to"], ["want", "to"], ["going", "to"],
        ["should"], ["must"], ["todo"], ["to-do"], ["for", "today"], ["for", "tomorrow"], ["for", "this", "week"], ["for", "next", "week"],
    ]

    /// Medium and high (cleanup-quality.md §5 P2.12): three or more short comma-separated tasks or things after an
    /// introducer, in the last sentence, become "- " lines ("For the offsite we need to book the venue, order catering,
    /// send the invites and set up the projector" → "…need to:\n- book the venue\n- order catering…"). The small model
    /// is unreliable at deciding what is a list, so the rules propose it and the prompt asks it to keep the layout.
    static func bullets(_ words: inout Words) {
        guard !words.isEmpty, !words.items.contains(where: { $0.gap.contains(where: \.isNewline) }) else { return }
        let start = words.sentenceStart(of: words.count - 1)
        let commas = (start + 1..<words.count).filter { Gap.hasComma(words[$0].gap) && !Gap.endsSentence(words[$0].gap) }
        guard commas.count >= 2, let first = introducerEnd(words, from: start, to: commas[0]) else { return }
        var items: [Range<Int>] = [first..<commas[0]]
        for (k, comma) in commas.enumerated() {
            let end = k + 1 < commas.count ? commas[k + 1] : words.count
            let lower = ["and", "or"].contains(words[comma].lower) ? comma + 1 : comma
            guard lower < end else { return }
            if k + 1 == commas.count, let and = (lower + 1..<end).first(where: { words[$0].lower == "and" && Gap.isSpace(words[$0].gap) }) {
                items += [lower..<and, and + 1..<end]
            } else {
                items.append(lower..<end)
            }
        }
        // Short phrases that start with a verb or a noun, never clauses with their own subject ("then we train…").
        let opener = Lexicon.continuationWords.union(Lexicon.subjectPronouns)
        guard items.count >= 3, items.allSatisfy({ range in
            (1...6).contains(range.count) && range.allSatisfy { !words[$0].isPlaceholder } && !opener.contains(words[range.lowerBound].lower)
                && !range.contains { Lexicon.subjectPronouns.contains(words[$0].lower) }
        }) else { return }
        var rebuilt = Array(words.items[..<first])
        for (n, range) in items.enumerated() {
            var item = Array(words.items[range])
            item[0].gap = n == 0 ? ":\n- " : "\n- "
            rebuilt += item
        }
        words.items = rebuilt
        words.tail = ""
    }

    /// Where the first item starts: right after the last introducer in the first chunk, with 1–6 words left for it.
    private static func introducerEnd(_ words: Words, from start: Int, to comma: Int) -> Int? {
        for p in stride(from: comma - 1, to: start, by: -1) where (1...6).contains(comma - p) {
            for phrase in introducers where p - phrase.count >= start && Disfluency.matches(phrase, in: words, at: p - phrase.count) {
                return p
            }
        }
        return nil
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

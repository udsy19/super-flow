import Foundation
import SuperFlowCore

// Speaker bleed (local-models.md §8.2, step 3): without headphones the microphone also hears the far end, so "You" can
// repeat what "Them" just said. A microphone segment is dropped only when it is a true echo: it lies within `slack` of
// system segments and at least `share` of its words appear, in order, in what they said. The user's own speech keeps
// most of its words its own even while talking over the far end, and answers under `minimumWords` are never dropped.
public enum MeetingEcho {
    static let slack: TimeInterval = 2
    static let share = 0.8
    static let minimumWords = 3

    /// Ids of the microphone segments (those near `range` when given) that echo the system track.
    public static func echoes(in segments: [TranscriptSegment], near range: ClosedRange<TimeInterval>? = nil) -> Set<UUID> {
        let system = segments.filter { $0.channel == .system && $0.isFinal }
        guard !system.isEmpty else { return [] }
        var echoes: Set<UUID> = []
        for mic in segments where mic.channel == .mic && mic.isFinal {
            if let range, mic.end < range.lowerBound - slack || mic.start > range.upperBound + slack { continue }
            if isEcho(mic, of: system) { echoes.insert(mic.id) }
        }
        return echoes
    }

    static func isEcho(_ mic: TranscriptSegment, of system: [TranscriptSegment]) -> Bool {
        let words = Grounding.words(mic.text)
        guard words.count >= minimumWords else { return false }
        let near = system.filter { $0.start - slack <= mic.end && mic.start <= $0.end + slack }.sorted { $0.start < $1.start }
        guard !near.isEmpty else { return false }
        let theirs = near.flatMap { Grounding.words($0.text) }
        return Double(commonWords(words, theirs)) >= share * Double(words.count)
    }

    /// Longest common subsequence of two word lists; words of four letters or more match one edit apart (an echo is
    /// recognised a little differently from the original).
    static func commonWords(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                let same = x == y || (min(x.count, y.count) >= 4 && TextDistance.edits(x, y) <= 1)
                current[j + 1] = same ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }
}

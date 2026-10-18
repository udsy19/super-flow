import Foundation
import SuperFlowCore

// Speakers of a meeting (behaviour.md §20.7.2–§20.7.3, local-models.md §8.4): the channel split gives "You" and "Them"
// for free; the diarizer splits "Them" into voices after the meeting; the user names them.

public extension Meeting {
    /// Labels every segment: the mic channel is "You"; system segments take the diarized voice that overlaps them most
    /// ("Speaker 1…n" in order of first appearance), or "Them" when there are no voices (no diarizer, or it failed).
    /// Speakers the user already named are kept as they are.
    mutating func assignSpeakers(voices turns: [TranscriptSegment]) {
        guard !speakers.contains(where: { $0.name != nil }) else { return }
        var speakers: [Speaker] = []
        if segments.contains(where: { $0.channel == .mic }) {
            let you = Speaker(label: AudioChannel.mic.liveLabel, channel: .mic)
            speakers.append(you)
            for i in segments.indices where segments[i].channel == .mic { segments[i].speakerID = you.id }
        }
        // Each system segment → the diarizer cluster with the largest overlap (nearest turn within 1 s when none overlap).
        var clusterOrder: [UUID] = []
        var clusterOfSegment: [Int: UUID] = [:]
        let order = segments.indices.filter { segments[$0].channel == .system }.sorted { segments[$0].start < segments[$1].start }
        for i in order {
            let segment = segments[i]
            var overlap: [UUID: TimeInterval] = [:]
            for turn in turns {
                guard let cluster = turn.speakerID else { continue }
                let shared = min(segment.end, turn.end) - max(segment.start, turn.start)
                if shared > 0 { overlap[cluster, default: 0] += shared }
            }
            let best = overlap.max { $0.value < $1.value }?.key ?? turns
                .filter { $0.speakerID != nil }
                .map { (cluster: $0.speakerID!, gap: max($0.start - segment.end, segment.start - $0.end)) }
                .filter { $0.gap <= 1 }
                .min { $0.gap < $1.gap }?.cluster
            guard let cluster = best else { continue }
            clusterOfSegment[i] = cluster
            if !clusterOrder.contains(cluster) { clusterOrder.append(cluster) }
        }
        if clusterOrder.isEmpty {
            if !order.isEmpty {
                let them = Speaker(label: AudioChannel.system.liveLabel, channel: .system)
                speakers.append(them)
                for i in order { segments[i].speakerID = them.id }
            }
        } else {
            let voices = clusterOrder.enumerated().map { Speaker(label: "Speaker \($0.offset + 1)", channel: .system) }
            let speakerOfCluster = Dictionary(uniqueKeysWithValues: zip(clusterOrder, voices.map(\.id)))
            speakers += voices
            for i in order { segments[i].speakerID = clusterOfSegment[i].flatMap { speakerOfCluster[$0] } }
            // Unmatched system segments keep the channel label; give them a "Them" speaker so they can be named too.
            let unmatched = order.filter { segments[$0].speakerID == nil }
            if !unmatched.isEmpty {
                let them = Speaker(label: AudioChannel.system.liveLabel, channel: .system)
                speakers.append(them)
                for i in unmatched { segments[i].speakerID = them.id }
            }
        }
        self.speakers = speakers
    }

    /// "Update everywhere": names a speaker in every block. A name another speaker of the same channel already has merges
    /// the two (the same person was split by the diarizer). An empty name clears it.
    mutating func renameSpeaker(_ id: UUID, to name: String) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = speakers[index].displayName
        if !trimmed.isEmpty, let twin = speakers.first(where: {
            $0.id != id && $0.channel == speakers[index].channel && $0.name?.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            for i in segments.indices where segments[i].speakerID == id { segments[i].speakerID = twin.id }
            speakers.remove(at: index)
        } else {
            speakers[index].name = trimmed.isEmpty ? nil : trimmed
        }
        renameOwner(from: previous, to: trimmed.isEmpty ? nil : trimmed)
    }

    /// "Update only this block": gives the run of consecutive same-speaker segments around `segmentID` to the speaker
    /// named `name` (an existing one, or a new one). Speakers left without segments are removed.
    mutating func assignBlock(containing segmentID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = segments.indices.sorted { segments[$0].start < segments[$1].start }
        guard !trimmed.isEmpty, let position = ordered.firstIndex(where: { segments[$0].id == segmentID }) else { return }
        let target = segments[ordered[position]]
        func sameBlock(_ i: Int) -> Bool { segments[i].speakerID == target.speakerID && segments[i].channel == target.channel }
        var first = position, last = position
        while first > 0, sameBlock(ordered[first - 1]) { first -= 1 }
        while last < ordered.count - 1, sameBlock(ordered[last + 1]) { last += 1 }

        let speaker: Speaker
        if let existing = speakers.first(where: { $0.channel == target.channel && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            speaker = existing
        } else {
            speaker = Speaker(label: trimmed, name: trimmed, channel: target.channel)
            speakers.append(speaker)
        }
        for i in ordered[first...last] { segments[i].speakerID = speaker.id }
        let used = Set(segments.compactMap(\.speakerID))
        speakers.removeAll { !used.contains($0.id) }
    }

    /// Action items owned by a renamed speaker follow the new name.
    private mutating func renameOwner(from old: String, to new: String?) {
        guard let new, old != new, var summary else { return }
        for i in summary.actionItems.indices where summary.actionItems[i].owner == old { summary.actionItems[i].owner = new }
        self.summary = summary
    }
}

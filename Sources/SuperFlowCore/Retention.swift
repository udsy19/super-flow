import Foundation

/// What gets deleted when (behaviour.md §11.2, §13.5, §20.9 and the owner decision: meeting audio 30 days, then
/// deleted; transcripts and notes kept forever by default, both changeable).
public enum RetentionPolicy {
    /// The stored value for "Never delete".
    public static let keepForever = 0

    /// The moment before which items are pruned for a retention in days; nil for forever.
    public static func cutoff(days: Int, now: Date = Date()) -> Date? {
        days <= keepForever ? nil : now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// Dictation history under the local data policy: `autoDelete24h` prunes a day back; `never` keeps nothing (the
    /// cutoff is now); `store` keeps everything.
    public static func dictationCutoff(policy: LocalDataPolicy, now: Date = Date()) -> Date? {
        switch policy {
        case .store: nil
        case .autoDelete24h: now.addingTimeInterval(-86_400)
        case .never: now
        }
    }

    /// Dictation audio kept for retry and playback (§2.3: 14 days).
    public static func dictationAudioCutoff(now: Date = Date()) -> Date {
        now.addingTimeInterval(-Double(DictationLimits.dictationAudioRetentionDays) * 86_400)
    }

    /// Whether a meeting's audio should be deleted now: it ended more than `audioDays` ago and still has audio. Audio
    /// that is the meeting's only record (nothing was transcribed: the engine failed or wasn't there) is kept, so
    /// "Retry transcript" still works and retention never deletes words that exist nowhere else.
    public static func shouldDeleteAudio(of meeting: Meeting, audioDays: Int, now: Date = Date()) -> Bool {
        guard meeting.hasAudio, meeting.hasTranscript, let ended = meeting.endedAt, let cutoff = cutoff(days: audioDays, now: now) else { return false }
        return ended < cutoff
    }

    /// Whether a whole meeting (transcript, notes, summary) should be deleted under the transcript retention.
    public static func shouldDeleteMeeting(_ meeting: Meeting, transcriptDays: Int, now: Date = Date()) -> Bool {
        guard let ended = meeting.endedAt, let cutoff = cutoff(days: transcriptDays, now: now) else { return false }
        return ended < cutoff
    }

    /// "30 days", "1 day", "Never delete".
    public static func label(days: Int) -> String {
        switch days {
        case ...keepForever: "Never delete"
        case 1: "1 day"
        case 365: "1 year"
        default: "\(days) days"
        }
    }
}

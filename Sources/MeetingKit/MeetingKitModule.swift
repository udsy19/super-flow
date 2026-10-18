import Combine
import Foundation
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum MeetingKitModule {
    @MainActor public static func install() {
        Services.meetingDetector = MeetingDetector.shared
        Services.meetingRecorder = MeetingRecorder.shared
        Services.summarizer = MeetingSummarizer.shared
    }
}

/// Placeholder detector (behaviour.md §20.3): no signals yet. The mic-holder monitor, bundle-id table, browser tab
/// scan and EventKit come next.
@MainActor
final class MeetingDetector: MeetingDetecting {
    static let shared = MeetingDetector()
    private var continuation: AsyncStream<MeetingSignal>.Continuation?
    private(set) lazy var signals: AsyncStream<MeetingSignal> = AsyncStream { self.continuation = $0 }
    private(set) var isRunning = false
    var activeMeetings: [DetectedMeeting] { [] }

    func start() { isRunning = true }
    func stop() { isRunning = false }
    func upcomingEvents(within: TimeInterval) async -> [CalendarEvent] { [] }
}

/// Placeholder recorder (behaviour.md §20.4–§20.7): refuses to start until dual-track capture exists. Audio retention
/// (`pruneAudio`) works against the store already, so the 30-day rule is enforced from day one.
@MainActor
final class MeetingRecorder: MeetingRecording {
    static let shared = MeetingRecorder()
    private let stateSubject = CurrentValueSubject<MeetingRecordingState, Never>(.idle)
    private var continuation: AsyncStream<TranscriptSegment>.Continuation?
    private(set) lazy var liveSegments: AsyncStream<TranscriptSegment> = AsyncStream { self.continuation = $0 }

    var state: MeetingRecordingState { stateSubject.value }
    var stateChanges: AnyPublisher<MeetingRecordingState, Never> { stateSubject.eraseToAnyPublisher() }

    func start(_ detected: DetectedMeeting?) async throws -> Meeting {
        throw AudioError.systemAudioUnsupported
    }

    func stop() async {}
    func discard() async {}

    @discardableResult func pruneAudio(now: Date) -> [UUID] {
        let days = Defaults[.meetingAudioRetentionDays]
        guard let cutoff = RetentionPolicy.cutoff(days: days, now: now) else { return [] }
        var pruned: [UUID] = []
        for var meeting in Services.meetings.meetingsWithAudio(before: cutoff) where RetentionPolicy.shouldDeleteAudio(of: meeting, audioDays: days, now: now) {
            try? FileManager.default.removeItem(at: SuperFlowPaths.meetingAudio.appendingPathComponent(meeting.id.uuidString))
            meeting.audioDeletedAt = now
            do {
                try Services.meetings.save(meeting)
                pruned.append(meeting.id)
            } catch {
                Log.meetings.error("Couldn't record audio deletion for \(meeting.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if !pruned.isEmpty { Log.meetings.info("Deleted audio of \(pruned.count) meeting(s) older than \(days) days") }
        return pruned
    }
}

/// Placeholder summarizer (behaviour.md §20.7, local-models.md §8.6).
@MainActor
final class MeetingSummarizer: MeetingSummarizing {
    static let shared = MeetingSummarizer()
    var isModelReady: Bool { false }
    func map(_ segments: [TranscriptSegment]) async throws -> MeetingSummary { throw SpeechError.engineUnavailable("Notes aren't available yet.") }
    func summarize(_ meeting: Meeting) async throws -> MeetingSummary { throw SpeechError.engineUnavailable("Notes aren't available yet.") }
    func ask(_ question: String, about meeting: Meeting) async throws -> String { throw SpeechError.engineUnavailable("Notes aren't available yet.") }
}

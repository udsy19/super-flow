import Foundation
import SuperFlowCore

/// Turns detector signals into the "Meeting detected — Record?" prompt (owner decision: always ask; nothing records
/// without a click, whatever `notetakerAutoStartEnabled` says) and ends a recording when its call ends
/// (`notetakerAutoEndEnabled`, confident ends only; behaviour.md §20.2–§20.4.5).
@MainActor
public final class MeetingPromptCoordinator {
    public static let shared = MeetingPromptCoordinator(detector: MeetingDetector.shared, recorder: MeetingRecorder.shared)

    /// Apps the user never wants to be asked about (bundle ids).
    static let neverAskKey = Defaults.Key<[String]>("meetingKit.neverAskApps", default: [])

    private let detector: MeetingDetecting
    private let recorder: MeetingRecorder
    private var listener: Task<Void, Never>?
    /// Meetings already asked about (answered or dismissed): not asked again until they end.
    private var asked: Set<String> = []
    /// Detected meetings until they end, so an end can be matched to a recording started from their calendar reminder.
    private var detected: [String: DetectedMeeting] = [:]

    public init(detector: MeetingDetecting, recorder: MeetingRecorder) {
        self.detector = detector
        self.recorder = recorder
    }

    public func start() {
        guard listener == nil else { return }
        let signals = detector.signals
        listener = Task { [weak self] in
            for await signal in signals { await self?.handle(signal) }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Don't-ask list

    public var neverAskApps: [String] { Defaults[Self.neverAskKey] }

    public func setNeverAsk(_ never: Bool, bundleID: String) {
        var apps = Defaults[Self.neverAskKey].filter { $0 != bundleID }
        if never { apps.append(bundleID) }
        Defaults[Self.neverAskKey] = apps
    }

    // MARK: Signals

    func handle(_ signal: MeetingSignal) async {
        switch signal {
        case .started(let meeting):
            detected[meeting.id] = meeting
            guard shouldAsk(about: meeting) else { return }
            asked.insert(meeting.id)
            ask(MeetingPrompt(title: meeting.title, platform: meeting.platform, calendarEvent: meeting.calendarEvent), for: meeting)
        case .ended(let id, let confident):
            asked.remove(id)
            let event = detected.removeValue(forKey: id)?.calendarEvent?.id
            let isRecorded = recorder.detectedMeetingID == id || (event != nil && recorder.currentMeeting?.calendarEventID == event)
            if confident, isRecorded, Defaults[.notetakerAutoEndEnabled], case .recording = recorder.state {
                Log.meetings.info("Call ended; stopping the Notetaker")
                await recorder.stop()
            }
        case .calendarReminder(let event, _):
            // A meeting that is already being recorded clears its reminder (§20.3).
            guard Defaults[.meetingDetection] == .notify, recorder.state.acceptsNewRecording, !asked.contains("calendar:" + event.id) else { return }
            asked.insert("calendar:" + event.id)
            let meeting = DetectedMeeting(id: "calendar:" + event.id, platform: event.platform ?? .other, title: event.title,
                                          url: event.joinURL?.absoluteString, calendarEvent: event)
            ask(MeetingPrompt(title: event.title, platform: meeting.platform, calendarEvent: event), for: meeting)
        }
    }

    private func shouldAsk(about meeting: DetectedMeeting) -> Bool {
        guard Defaults[.meetingDetection] == .notify, recorder.state.acceptsNewRecording, !asked.contains(meeting.id) else { return false }
        if let app = meeting.bundleID, neverAskApps.contains(app) { return false }
        // The calendar reminder for this event already asked.
        if let event = meeting.calendarEvent, asked.contains("calendar:" + event.id) { return false }
        return true
    }

    private func ask(_ prompt: MeetingPrompt, for meeting: DetectedMeeting) {
        guard let flowBar = Services.flowBar else { return }
        flowBar.showMeetingPrompt(prompt) { [weak self] answer in
            guard let self else { return }
            switch answer {
            case .record:
                Task { @MainActor in
                    do { try await self.recorder.start(meeting) } catch {
                        Log.meetings.error("Couldn't start recording: \(error.localizedDescription, privacy: .public)")
                    }
                }
            case .neverForThisApp:
                if let app = meeting.bundleID { self.setNeverAsk(true, bundleID: app) }
            case .notThisOne, .dismissed:
                break
            }
        }
    }
}

extension MeetingRecordingState {
    /// A new recording may start: nothing is being captured (an earlier meeting may still be processing).
    var acceptsNewRecording: Bool {
        switch self {
        case .idle, .processing: true
        case .starting, .recording, .stopping: false
        }
    }
}

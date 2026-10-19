import Foundation

/// Late-bound registry: each module's `install()` assigns its implementations at launch, in the order the app
/// target calls them (see Sources/SuperFlow/main.swift). Modules call each other only through these.
@MainActor
public enum Services {
    /// FlowStore.
    public static var history: HistoryStoring!
    /// FlowStore (the same object as `history`).
    public static var meetings: MeetingStoring!
    /// AudioKit.
    public static var audio: AudioCapturing!
    /// SpeechKit.
    public static var speech: SpeechRecognizing!
    /// SpeechKit.
    public static var models: ModelManaging!
    /// CleanupKit.
    public static var cleanup: TextCleaning!
    /// InsertionKit.
    public static var insertion: TextInserting!
    /// InsertionKit.
    public static var hotkeys: HotkeyMonitoring!
    /// InsertionKit.
    public static var context: AppContextReading!
    /// FlowBarKit.
    public static var flowBar: FlowBarPresenting!
    /// HubKit.
    public static var hub: HubPresenting!
    /// HubKit.
    public static var onboarding: OnboardingPresenting!
    /// MeetingKit.
    public static var meetingDetector: MeetingDetecting!
    /// MeetingKit.
    public static var meetingRecorder: MeetingRecording!
    /// MeetingKit.
    public static var summarizer: MeetingSummarizing!
    /// SuperFlow (the app target): the dictation state machine every surface reads.
    public static var dictation: DictationControlling!
    /// UpdateKit.
    public static var updates: Updating!
}

/// Where Super Flow keeps its files: ~/Library/Application Support/Super Flow/ (behaviour.md §1.4).
public enum SuperFlowPaths {
    public static let bundleID = Bundle.main.bundleIdentifier ?? "com.udsy.superflow"
    /// The folder `support` lives in: Application Support. The self-test points it at a temporary folder so it never
    /// creates or touches the real one.
    nonisolated(unsafe) public static var base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    public static let supportFolderName = "Super Flow"
    public static var support: URL { ensure(base.appendingPathComponent(supportFolderName, isDirectory: true)) }
    /// The SQLite database (with -wal and -shm next to it).
    public static var database: URL { support.appendingPathComponent("store.sqlite") }
    /// Downloaded models, `Models/<kind>/<file>` (local-models.md §5.2). Partial downloads sit next to them as `.partial`.
    public static var models: URL { ensure(support.appendingPathComponent("Models", isDirectory: true)) }
    public static func models(_ kind: ModelKind) -> URL { ensure(models.appendingPathComponent(kind.rawValue, isDirectory: true)) }
    /// Dictation audio kept for retry/playback, `Audio/Dictations/<id>.caf`.
    public static var dictationAudio: URL { ensure(support.appendingPathComponent("Audio/Dictations", isDirectory: true)) }
    /// Meeting audio, one folder per meeting with one file per channel (`Audio/Meetings/<id>/mic.caf`, `system.caf`).
    public static var meetingAudio: URL { ensure(support.appendingPathComponent("Audio/Meetings", isDirectory: true)) }
    public static func meetingAudio(_ meetingID: UUID) -> URL {
        ensure(meetingAudio.appendingPathComponent(meetingID.uuidString, isDirectory: true))
    }
    /// Compiled Core ML caches.
    public static var caches: URL {
        ensure(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportFolderName, isDirectory: true))
    }
    /// A damaged database is moved here before starting over.
    public static var backup: URL { ensure(support.appendingPathComponent("Backup", isDirectory: true)) }

    /// Free bytes for important use on the volume that holds `url`; `Int64.max` when the system can't say, so a failed
    /// query never stops a recording.
    public static func freeSpace(at url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    @discardableResult public static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

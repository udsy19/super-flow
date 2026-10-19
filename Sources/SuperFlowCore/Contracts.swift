import AppKit
import Combine

// Service contracts. Each protocol has one owning module whose `<Module>Module.install()` registers the
// implementation in `Services`. UI-facing protocols are `@MainActor`; engines are `Sendable` actors or classes that do
// their work off the main actor and hand results back as values.

// MARK: - Audio (AudioKit; behaviour.md §4, §20.4)

public struct AudioDevice: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isBuiltIn: Bool
    public var isVirtual: Bool
    /// "Laptop lid is closed", "Put on your headset to use it"; nil when usable.
    public var unavailableReason: String?

    public init(id: String, name: String, isBuiltIn: Bool = false, isVirtual: Bool = false, unavailableReason: String? = nil) {
        self.id = id; self.name = name; self.isBuiltIn = isBuiltIn; self.isVirtual = isVirtual; self.unavailableReason = unavailableReason
    }
}

/// A 40 ms block of 16 kHz mono samples with its channel and host time (local-models.md §9.1).
public struct AudioFrame: Sendable {
    public var channel: AudioChannel
    public var samples: [Float]
    public var time: TimeInterval
    /// RMS level 0…1 after the adaptive scaler (ui-reference.md §2.7).
    public var level: Float

    public init(channel: AudioChannel, samples: [Float], time: TimeInterval, level: Float) {
        self.channel = channel; self.samples = samples; self.time = time; self.level = level
    }
}

/// How system audio can be captured on this Mac (§15, §20.4.2).
public enum SystemAudioMethod: String, Codable, Sendable {
    case processTap = "process_tap"
    case screenCaptureKit = "screen_capture_kit"
    case unsupported
}

public enum AudioError: LocalizedError, Equatable {
    case permissionDenied
    case deviceUnavailable(String)
    case noAudio
    case systemAudioUnsupported

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone access isn't allowed."
        case .deviceUnavailable(let name): "\(name) isn't available."
        case .noAudio: "We're not hearing anything."
        case .systemAudioUnsupported: "System audio can't be captured on this Mac."
        }
    }
}

@MainActor
public protocol AudioCapturing: AnyObject {
    var devices: [AudioDevice] { get }
    /// The device dictation uses: the override, else the top of the ranking, else the built-in mic.
    var selectedDevice: AudioDevice? { get }
    var isCapturingMicrophone: Bool { get }
    var isCapturingSystemAudio: Bool { get }
    var systemAudioMethod: SystemAudioMethod { get }
    /// Starts the microphone (with `DictationLimits.preRoll` of history) and begins delivering `.mic` frames.
    func startMicrophone() async throws
    func stopMicrophone()
    /// Starts the system-audio tap and begins delivering `.system` frames (meetings only).
    func startSystemAudio() async throws
    func stopSystemAudio()
    /// Every frame from every running capture, in order.
    var frames: AsyncStream<AudioFrame> { get }
    /// The microphone level 0…1 for the Flow Bar waveform, batched every 150 ms.
    var level: AnyPublisher<Float, Never> { get }
    /// The input devices whenever they come, go or change availability (the current list first).
    var deviceChanges: AnyPublisher<[AudioDevice], Never> { get }
    /// Lowers the output volume while dictating when "Mute all audio while dictating" is on; restored by `unmuteOutput`.
    func muteOutput()
    func unmuteOutput()
    func play(_ cue: SoundCue)
}

/// Cue sounds (behaviour.md §17).
public enum SoundCue: String, CaseIterable, Sendable {
    case dictationStart, dictationStop, handsFreeLock, paste, notificationSuccess, notificationError, notificationAlert, achievement
}

// MARK: - Speech (SpeechKit; local-models.md §2, §9.1)

@MainActor
public protocol SpeechRecognizing: AnyObject {
    /// Engines that are installed and can be prepared, by `ModelDescriptor.id`.
    var availableEngines: [String] { get }
    /// The engine the next dictation uses (`Defaults[.asrModelID]` once it is installed and warmed).
    var activeEngineID: String? { get }
    /// Loads and warms the engine for `modelID`; the previous engine stays until this one is ready.
    func prepare(modelID: String) async throws
    func unload()
    /// Recognises one clip. Dictation jobs pre-empt meeting jobs.
    func transcribe(_ audio: AudioClip, options: TranscriptionOptions, priority: SpeechPriority) async throws -> Transcript
    /// Recognises audio as it arrives: closed VAD segments while the key is held, the tail on finish.
    func transcribeIncrementally(_ audio: AsyncStream<AudioClip>, options: TranscriptionOptions, priority: SpeechPriority)
        -> AsyncThrowingStream<TranscriptionEvent, Error>
    /// Speech regions in a clip (Silero), as sample ranges.
    func speechSegments(in audio: AudioClip) async -> [Range<Int>]
    /// Post-meeting speaker split of one channel.
    func diarize(_ audio: AudioClip) async throws -> [TranscriptSegment]
}

public enum SpeechError: LocalizedError, Equatable {
    case modelNotInstalled(String)
    case engineUnavailable(String)
    case noSpeech
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let id): "The model \(id) isn't downloaded."
        case .engineUnavailable(let why): why
        case .noSpeech: "We couldn't hear you."
        case .failed(let why): why
        }
    }
}

// MARK: - Models (SpeechKit; local-models.md §5)

/// Owner decision: models download automatically in the background after install, with no prompt and no setup step.
/// `AutoDownloadPolicy` holds the rules the manager applies; `Defaults[.autoDownloadModels]` turns it off.
public enum AutoDownloadPolicy {
    /// Download order: the speech models first so dictation is ready as soon as possible, then cleanup, then notes.
    /// VAD is bundled, so it never downloads. The ids come from the preset for this Mac (`ModelCatalog.preset`).
    public static func order(for preset: ModelCatalog.Preset) -> [ModelDescriptor] {
        let asr = preset.dictation.filter { $0.kind == .asr }
        let cleanup = preset.dictation.filter { $0.kind == .llm }
        let notes = preset.meetings.filter { $0.kind == .llm }
        let rest = preset.meetings.filter { $0.kind != .llm }
        var seen: Set<String> = []
        return (asr + cleanup + notes + rest).filter { seen.insert($0.id).inserted }
    }
    /// Skip when the free space on the models volume is below this; retry daily.
    public static let minimumFreeDisk: Int64 = 10 << 30
    public static let diskRetryInterval: TimeInterval = 24 * 3600
    /// Never on expensive (hotspot) or constrained (Low Data Mode) paths; paused in Low Power Mode.
    public static let allowsExpensiveNetwork = false
    public static let allowsConstrainedNetwork = false
    public static let pausesInLowPowerMode = true
    /// One transfer at a time, range requests with resume, so the user's own traffic is never saturated.
    public static let maxConcurrentDownloads = 1
    /// While the user is dictating or in a meeting, downloads yield (pause) and resume afterwards.
    public static let yieldsWhileBusy = true
}

/// Why automatic downloads are not running right now (shown in Settings › Models, never as an interruption).
public enum AutoDownloadStatus: Equatable, Sendable {
    case idle
    case downloading(modelID: String, progress: DownloadProgress)
    case upToDate
    case disabled
    case waitingForNetwork
    case waitingForPower
    case waitingForDisk(freeBytes: Int64)
    case waitingWhileBusy
}

@MainActor
public protocol ModelManaging: AnyObject {
    var catalog: [ModelDescriptor] { get }
    func state(of id: String) -> ModelState
    /// Where an installed model lives (file or folder); nil until installed.
    func location(of id: String) -> URL?
    /// Downloads with resume and streaming SHA-256; one download at a time. The stream ends after the final
    /// verification, or throws (`ModelError`). Explicit downloads (Settings, "Download" button) jump the automatic queue.
    func download(_ id: String) -> AsyncThrowingStream<DownloadProgress, Error>
    func pause(_ id: String)
    func delete(_ id: String) throws
    /// Copies a user-supplied file in after verifying its hash ("Import model file…").
    func importModel(_ id: String, from file: URL) async throws
    /// Bytes used under `SuperFlowPaths.models`.
    var diskUsage: Int64 { get }
    /// Published whenever any model's state changes (the id), including progress of the automatic queue.
    var changes: AnyPublisher<String, Never> { get }

    // MARK: Automatic downloads (`AutoDownloadPolicy`)

    /// Starts the background queue: called at launch (also during onboarding) and whenever the policy inputs change.
    /// It resumes partial files, follows `AutoDownloadPolicy`, and stops itself when `Defaults[.autoDownloadModels]` is off.
    func startAutomaticDownloads()
    var autoDownloadStatus: AutoDownloadStatus { get }
    /// Dictation or a meeting started/ended: the queue yields while busy (`AutoDownloadPolicy.yieldsWhileBusy`).
    func setUserBusy(_ busy: Bool)
    /// Progress of the model a feature needs, for the Flow Bar's "Getting ready… 40%" state; nil when installed or not queued.
    func readiness(of id: String) -> Double?
}

public enum ModelError: LocalizedError, Equatable {
    case unknownModel(String)
    case notEnoughSpace(needed: Int64)
    case checksumMismatch
    case http(Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unknownModel(let id): "Unknown model \(id)."
        case .notEnoughSpace(let needed): "Needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) free."
        case .checksumMismatch: "Download damaged."
        case .http(let status): "The download failed (HTTP \(status))."
        case .cancelled: "Download paused."
        }
    }
}

// MARK: - Cleanup and transforms (CleanupKit; behaviour.md §8, §10; local-models.md §3)

/// Everything the cleanup pass may use for one utterance.
public struct CleanupInput: Sendable {
    public var transcript: Transcript
    public var context: AppContext
    public var style: WritingStyle
    public var level: CleanupLevel
    public var format: TranscriptionFormat
    public var dictionary: [DictionaryEntry]
    public var snippets: [Snippet]
    /// Style detection (§8.4, `Defaults[.styleDetectionEnabled]`): when the text before the cursor is long enough to
    /// show how the user writes there, that style replaces `style`.
    public var detectStyle: Bool

    public init(transcript: Transcript, context: AppContext = AppContext(), style: WritingStyle = .formal, level: CleanupLevel = .light,
                format: TranscriptionFormat = .aiFormatting, dictionary: [DictionaryEntry] = [], snippets: [Snippet] = [],
                detectStyle: Bool = false) {
        self.transcript = transcript; self.context = context; self.style = style; self.level = level; self.format = format
        self.dictionary = dictionary; self.snippets = snippets; self.detectStyle = detectStyle
    }
}

/// Key presses the inserter performs after pasting ("press enter", file tagging Tab) (§8.3).
public enum PostInsertAction: String, Codable, Hashable, Sendable {
    case pressReturn, pressTab
}

/// Why the LLM stage was skipped (local-models.md §3.6, Flow's `format_skip_reason` names).
public enum CleanupSkipReason: String, Codable, Sendable {
    case clientDisabled = "client_disabled"
    case emptyTranscript = "empty_transcript"
    case insufficientInput = "formatter_insufficient_input"
    case unsupportedLanguage = "formatter_unsupported_language"
    case timeout = "formatter_timeout"
    case emptyOutput = "formatter_empty_output"
    case hallucination = "formatter_hallucination"
    case error = "formatter_error"
}

public struct CleanupOutput: Sendable {
    public var text: String
    /// Set when the text is the rules-only result.
    public var skipReason: CleanupSkipReason?
    public var actions: [PostInsertAction]
    /// Snippets whose trigger was spoken and expanded, for their use counts (§8.6).
    public var expandedSnippets: [UUID]
    public var usedLLM: Bool { skipReason == nil }

    public init(text: String, skipReason: CleanupSkipReason? = nil, actions: [PostInsertAction] = [], expandedSnippets: [UUID] = []) {
        self.text = text; self.skipReason = skipReason; self.actions = actions; self.expandedSnippets = expandedSnippets
    }
}

/// Which local LLM a request runs on (local-models.md §9.2): the cleanup model (`Defaults[.cleanupModelID]`, Qwen3.5-2B
/// by default) for dictation cleanup, Transforms and Command Mode; the notes model (`Defaults[.notesModelID]`,
/// Qwen3.5-4B) for meeting notes. One engine serves both roles when both settings name the same model.
public enum LanguageModelRole: String, Codable, CaseIterable, Sendable {
    case cleanup, notes
}

/// Transform and Command Mode failures, worded as strings.md's `polish_*` notifications.
public enum TransformError: LocalizedError, Equatable {
    /// More than `DictationLimits.transformMaxWords` words selected.
    case tooLong
    case emptyResponse
    case timedOut
    /// The model for the role is not downloaded or not loaded yet.
    case modelNotReady
    case failed

    public var errorDescription: String? {
        switch self {
        case .tooLong: "Oops, too long to polish"
        case .emptyResponse: "Transform returned no text"
        case .timedOut: "Transform timed out"
        case .modelNotReady: "Just a moment - Super Flow is getting ready..."
        case .failed: "Transform failed. Please try again."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .tooLong: "Try again with under \(DictationLimits.transformMaxWords) words"
        case .emptyResponse: "Something went wrong. Please try again."
        case .timedOut: "The request took too long. Please try again."
        case .modelNotReady, .failed: nil
        }
    }
}

@MainActor
public protocol TextCleaning: AnyObject {
    /// Whether the model for a role is loaded; cleanup still works (rules only) without the cleanup model.
    func isModelReady(for role: LanguageModelRole) -> Bool
    /// Loads and warms a GGUF for a role; the previous engine of that role stays until this one is ready.
    func prepare(modelID: String, role: LanguageModelRole) async throws
    func unload(role: LanguageModelRole)
    /// Prefills the per-app system prefix so the user turn is all that remains (call at key-down).
    func warm(style: WritingStyle, level: CleanupLevel, category: AppCategory) async
    /// Never throws: falls back to rules with a skip reason. `budget` is the LLM wall-time cap.
    func clean(_ input: CleanupInput, budget: TimeInterval) async -> CleanupOutput
    /// Transforms (Polish and custom prompts) and Command Mode over selected text on the cleanup model; throws on failure.
    func transform(_ text: String, instruction: String) async throws -> String
    /// A free-form instruction over `input` on the model of `role` (MeetingKit's notes on the notes model); the reply
    /// is returned as written, with no guardrails beyond the think-block strip. Throws `TransformError`.
    func generate(_ input: String, instruction: String, role: LanguageModelRole) async throws -> String
}

public extension TextCleaning {
    /// The cleanup model is loaded.
    var isModelReady: Bool { isModelReady(for: .cleanup) }
}

// MARK: - Insertion and context (InsertionKit; behaviour.md §6, §9)

public enum InsertionMethod: String, Codable, CaseIterable, Sendable {
    /// Pasteboard + synthetic ⌘V, previous clipboard restored afterwards.
    case paste
    /// Accessibility `AXValue` write at the caret when the element allows it; paste otherwise.
    case accessibility
}

public enum InsertionOutcome: Equatable, Sendable {
    case inserted
    /// Nothing editable had focus or the paste was not picked up. The user's clipboard is as it was (the caller keeps
    /// the words reachable); only without Accessibility (`accessibility_not_trusted`) is the text left on the clipboard.
    case notInserted(reason: String)
    case blockedSecureField
}

@MainActor
public protocol TextInserting: AnyObject {
    func insert(_ text: String, actions: [PostInsertAction], method: InsertionMethod) async -> InsertionOutcome
    /// The selected text of the focused element (AX, then copy-based fallback); nil when none.
    func selectedText() async -> String?
    /// Replaces the selection with `text` (Transforms, Command Mode).
    func replaceSelection(with text: String) async -> InsertionOutcome
    func copyToClipboard(_ text: String)
    /// What the user changed the last inserted text into, when they edited it within the watch window (§9.4); nil otherwise.
    func observeEdits(of insertedText: String, window: TimeInterval) async -> String?
}

@MainActor
public protocol AppContextReading: AnyObject {
    /// The frontmost app and its text context at this moment (`useAxContext` off: app only).
    func snapshot() -> AppContext
    var frontmostApp: AppRecord? { get }
}

// MARK: - Hotkeys (InsertionKit; behaviour.md §3)

/// How the event tap was installed (§3.3, §15).
public enum HotkeyTapMode: String, Sendable {
    /// Accessibility granted: completed chords are swallowed before the frontmost app sees them.
    case active
    /// Input Monitoring only: shortcuts fire but every key still reaches the app.
    case listenOnly = "listen-only"
}

@MainActor
public protocol HotkeyMonitoring: AnyObject {
    var isRunning: Bool { get }
    /// The tap installed right now; nil while no permission allows one.
    var tapMode: HotkeyTapMode? { get }
    /// Starts the event tap (needs Accessibility); throws when it cannot be created.
    func start() throws
    func stop()
    func update(_ map: ShortcutMap)
    var events: AsyncStream<HotkeyEvent> { get }
    /// While a shortcut recorder is open, chords go to `recorderEvents` instead of `events`.
    var isRecording: Bool { get set }
    var recorderEvents: AsyncStream<KeyChord> { get }
    /// Whether the connected keyboard has an Fn key (Apple keyboards do).
    var hasFnKey: Bool { get }
}

// MARK: - Flow Bar (FlowBarKit; behaviour.md §5, §18; ui-reference.md §2)

/// Which edge the bar is docked to.
public enum FlowBarEdge: String, Codable, CaseIterable, Sendable {
    case bottom, left, right
}

/// The pill's visual state (ui-reference.md §2.4).
public enum FlowBarState: Equatable, Sendable {
    case hidden
    case resting
    case ready
    case initializing
    case listening(mode: DictationMode)
    case processing
    /// A feature was used before its model finished downloading: "Getting ready… 40%" instead of an error.
    case preparing(fraction: Double)
    case transformProcessing(label: String)
    case transformCompleted
    case cleanupCompleted
    case error
    case meeting(MeetingBarPhase)
}

public enum MeetingBarPhase: Equatable, Sendable {
    case pending
    /// `startedAt` is the recording's start, so the bar's clock survives restarts and dictations in between.
    case recording(wordCount: Int, startedAt: Date)
    case reconnecting, stopping
}

/// A card shown above the bar (§18): in-app, never a macOS banner.
public struct FlowBarNotification: Equatable, Sendable {
    public enum Variant: Sendable { case mini, condensed, standard, error, alert, success }
    public var id: String
    public var title: String
    public var subtitle: String?
    public var variant: Variant
    /// Seconds before auto-dismiss, nil to stay until dismissed.
    public var timeout: TimeInterval?
    public var actions: [String]

    public init(id: String, title: String, subtitle: String? = nil, variant: Variant = .mini, timeout: TimeInterval? = 10,
                actions: [String] = []) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.variant = variant; self.timeout = timeout; self.actions = actions
    }
}

/// The "Meeting detected — Record?" prompt (owner decision: always ask, never record without a click).
public struct MeetingPrompt: Equatable, Sendable {
    public var title: String
    public var platform: MeetingPlatform
    public var calendarEvent: CalendarEvent?
    public var timeout: TimeInterval

    public init(title: String, platform: MeetingPlatform, calendarEvent: CalendarEvent? = nil, timeout: TimeInterval = 30) {
        self.title = title; self.platform = platform; self.calendarEvent = calendarEvent; self.timeout = timeout
    }
}

public enum MeetingPromptAnswer: Equatable, Sendable {
    case record, notThisOne
    /// "Don't ask for this app": the prompt is never shown again for the meeting's app.
    case neverForThisApp
    case dismissed
}

@MainActor
public protocol FlowBarPresenting: AnyObject {
    var state: FlowBarState { get }
    /// Dictation states. `.meeting(…)` here is the same as `setMeetingPhase`; `.resting`/`.hidden` end a dictation and
    /// bring the meeting chrome back when a meeting is recording.
    func setState(_ state: FlowBarState)
    /// The Notetaker's layer under the dictation states (§10.2): a phase while a meeting records, nil when it ends.
    func setMeetingPhase(_ phase: MeetingBarPhase?)
    /// Microphone level 0…1 for the waveform.
    func setLevel(_ level: Float)
    func setEdge(_ edge: FlowBarEdge)
    /// "Hide for 1 hour" / "Show Flow Bar at all times" off; active states still show.
    func setRestingVisible(_ visible: Bool)
    func show(_ notification: FlowBarNotification, onAction: @escaping (String) -> Void)
    func dismiss(notificationID: String)
    func showMeetingPrompt(_ prompt: MeetingPrompt, onAnswer: @escaping (MeetingPromptAnswer) -> Void)
    /// Live streaming text panel above the bar during hands-free dictation.
    func showLiveText(_ text: String?)
}

// MARK: - Hub and onboarding (HubKit; behaviour.md §12–§14)

public enum HubPage: String, Codable, CaseIterable, Sendable {
    case home, history, notetaker, tasks, dictionary, snippets, style, transforms, scratchpad, insights, settings
}

public enum SettingsPane: String, Codable, CaseIterable, Sendable {
    case general, system, notetaker, models, vibeCoding = "vibe-coding", experimental, dataAndPrivacy = "data-and-privacy", about
}

@MainActor
public protocol HubPresenting: AnyObject {
    func show(_ page: HubPage)
    func showSettings(_ pane: SettingsPane)
    func showMeeting(_ id: UUID)
    /// The Notepad window for a meeting being recorded (§20.6).
    func showNotepad(for meetingID: UUID)
    /// The Flow Bar's Quick note (§11.4): Notes with a fresh note in front and its editor focused, so the next
    /// dictation lands in it.
    func showQuickNote()
    var isVisible: Bool { get }
}

@MainActor
public protocol OnboardingPresenting: AnyObject {
    var isCompleted: Bool { get }
    func show()
    /// "Restart tutorial": Microphone → Shortcut → Try it.
    func restartTutorial()
}

// MARK: - Meetings (MeetingKit; behaviour.md §20)

/// A meeting the detector believes is happening (§20.3).
public struct DetectedMeeting: Equatable, Identifiable, Sendable {
    public var id: String
    public var platform: MeetingPlatform
    public var title: String
    public var bundleID: String?
    public var url: String?
    public var calendarEvent: CalendarEvent?
    public var detectedAt: Date

    public init(id: String, platform: MeetingPlatform, title: String, bundleID: String? = nil, url: String? = nil,
                calendarEvent: CalendarEvent? = nil, detectedAt: Date = Date()) {
        self.id = id; self.platform = platform; self.title = title; self.bundleID = bundleID; self.url = url
        self.calendarEvent = calendarEvent; self.detectedAt = detectedAt
    }
}

public enum MeetingSignal: Equatable, Sendable {
    case started(DetectedMeeting)
    /// The conference app released the mic or its window went away; `confident` false asks "Stop taking notes?".
    case ended(id: String, confident: Bool)
    case calendarReminder(CalendarEvent, startsIn: TimeInterval)
}

@MainActor
public protocol MeetingDetecting: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
    var activeMeetings: [DetectedMeeting] { get }
    var signals: AsyncStream<MeetingSignal> { get }
    /// Upcoming calendar meetings (EventKit, read-only); empty without Calendar access.
    func upcomingEvents(within: TimeInterval) async -> [CalendarEvent]
}

public enum MeetingRecordingState: Equatable, Sendable {
    case idle, starting, recording(meetingID: UUID), stopping(meetingID: UUID), processing(meetingID: UUID, stage: String)
}

@MainActor
public protocol MeetingRecording: AnyObject {
    var state: MeetingRecordingState { get }
    var stateChanges: AnyPublisher<MeetingRecordingState, Never> { get }
    /// Starts mic + system capture for a detected meeting (or a manual note when nil); returns the meeting.
    @discardableResult func start(_ detected: DetectedMeeting?) async throws -> Meeting
    /// Stops, then runs refine → diarize → summarize in the background (`state` reports the stage).
    func stop() async
    /// Discards a meeting started by mistake: audio, transcript and row.
    func discard() async
    /// Final and partial segments as they arrive, for the live transcript.
    var liveSegments: AsyncStream<TranscriptSegment> { get }
    /// Appends the user's text to the notes of the meeting being recorded (the Notepad, dictation into it).
    func appendNote(_ text: String)
    /// Marks the current moment of the recording (`Meeting.markers`): "Pricing", or an empty label for a plain bookmark.
    func addMarker(_ label: String)
    /// "Update everywhere" (§20.7.3): names a speaker in every block; the meeting's action items follow the new name.
    func renameSpeaker(_ speakerID: UUID, to name: String, inMeeting id: UUID) throws
    /// Deletes audio past retention (`Defaults[.meetingAudioRetentionDays]`); returns the meetings pruned.
    @discardableResult func pruneAudio(now: Date) -> [UUID]
    /// "Retry transcript": transcribes a finished meeting again from its saved audio (the engine failed or wasn't ready),
    /// then speakers and notes. Throws when nothing could be transcribed.
    func retryTranscript(of id: UUID) async throws
    /// "Generate summary": writes the notes again from the saved transcript and the user's notes (after the notes model
    /// failed or wasn't ready). Throws why it couldn't.
    func regenerateNotes(of id: UUID) async throws
}

@MainActor
public protocol MeetingSummarizing: AnyObject {
    var isModelReady: Bool { get }
    /// Rolling "map" over a chunk of finalised transcript (local-models.md §8.6).
    func map(_ segments: [TranscriptSegment]) async throws -> MeetingSummary
    /// Final notes from the chunk notes, the transcript and the user's notes.
    func summarize(_ meeting: Meeting) async throws -> MeetingSummary
    /// "Ask anything" over one meeting.
    func ask(_ question: String, about meeting: Meeting) async throws -> String
}

// MARK: - Store (FlowStore; behaviour.md §11, §19)

public enum StoreChange: Equatable, Sendable {
    case dictations, dictionary, snippets, notes, meetings, actionItems
    /// Erase, prune, reset: reload everything.
    case reloaded
}

public enum StoreError: LocalizedError, Equatable {
    case notFound(UUID)
    case invalid(String)
    case database(String)
    /// The disk is full: nothing more can be written until space is freed.
    case storageFull

    public var errorDescription: String? {
        switch self {
        case .notFound: "The item doesn't exist."
        case .invalid(let why): why
        case .database(let message): message
        case .storageFull: "You are running out of space on your computer."
        }
    }
}

/// Dictations, the dictionary, snippets and transforms (§11.1, §8.5, §8.6).
@MainActor
public protocol HistoryStoring: AnyObject {
    func dictation(_ id: UUID) -> Dictation?
    /// Newest first; `query` matches raw and cleaned text by word prefix, ignoring case and diacritics.
    func dictations(matching query: String, limit: Int, offset: Int) -> [Dictation]
    var lastDictation: Dictation? { get }
    func save(_ dictation: Dictation) throws
    func deleteDictation(_ id: UUID) throws
    /// Deletes dictations older than the cutoff, with their audio; returns the count.
    @discardableResult func pruneDictations(before cutoff: Date) throws -> Int
    /// Deletes the audio of dictations older than the cutoff (`RetentionPolicy.dictationAudioCutoff`, 14 days) and keeps
    /// their text. Audio that is the only record of a dictation (nothing was transcribed: the engine failed, or it was
    /// cancelled or interrupted) stays for "Retry transcript". Returns how many files went.
    @discardableResult func pruneDictationAudio(before cutoff: Date) throws -> Int
    @discardableResult func eraseDictations() throws -> Int
    /// Words dictated and dictation count, for Insights.
    func statistics(since: Date) -> (dictations: Int, words: Int, seconds: TimeInterval)

    var dictionary: [DictionaryEntry] { get }
    func save(_ entry: DictionaryEntry) throws
    func deleteDictionaryEntry(_ id: UUID) throws

    var snippets: [Snippet] { get }
    func save(_ snippet: Snippet) throws
    func deleteSnippet(_ id: UUID) throws

    var transforms: [TransformPrompt] { get }
    func save(_ transform: TransformPrompt) throws
    func deleteTransform(_ id: UUID) throws

    /// The Notes page (§11.4), newest edit first.
    var notes: [ScratchNote] { get }
    func save(_ note: ScratchNote) throws
    func deleteNote(_ id: UUID) throws

    var changes: AnyPublisher<StoreChange, Never> { get }
}

/// Meetings, their segments and summaries, and action items across meetings (§20.8).
@MainActor
public protocol MeetingStoring: AnyObject {
    func meeting(_ id: UUID) -> Meeting?
    /// Newest first; `query` matches title, transcript, notes and summary.
    func meetings(matching query: String, limit: Int, offset: Int) -> [Meeting]
    func save(_ meeting: Meeting) throws
    /// Removes the row and its audio folder.
    func deleteMeeting(_ id: UUID) throws
    /// Meetings whose audio is older than the cutoff and not yet deleted.
    func meetingsWithAudio(before cutoff: Date) -> [Meeting]
    /// Transcript retention (`Defaults[.meetingTranscriptRetentionDays]`): deletes whole meetings older than the cutoff.
    @discardableResult func pruneMeetings(before cutoff: Date) throws -> Int

    var actionItems: [ActionItem] { get }
    func save(_ item: ActionItem) throws
    func deleteActionItem(_ id: UUID) throws

    /// `.meetings`, `.actionItems` and `.reloaded` as rows change (the same feed as `HistoryStoring.changes` when one
    /// store backs both).
    var changes: AnyPublisher<StoreChange, Never> { get }
}

// MARK: - Dictation coordinator (SuperFlow app target; behaviour.md §2)

@MainActor
public protocol DictationControlling: AnyObject {
    var status: DictationStatus { get }
    var mode: DictationMode? { get }
    var statusChanges: AnyPublisher<DictationStatus, Never> { get }
    func start(mode: DictationMode, source: DictationSource)
    /// Finishes a recording and inserts (release of PTT, second hands-free press, Finish button).
    func finish()
    func dismiss(_ reason: DismissReason)
    func pasteLastTranscript()
    func copyLastTranscript()
    /// "Retry transcript" in History: recognises and cleans a dictation's saved audio again (one that failed, was
    /// cancelled or interrupted by a crash) and updates its row. Throws `DictationRetryError` or the engine's error.
    func retryTranscription(_ id: UUID) async throws
}

/// Why "Retry transcript" couldn't run (strings.md `hub_history_*retry*`).
public enum DictationRetryError: LocalizedError, Equatable {
    case busy
    case audioUnavailable

    public var errorDescription: String? {
        switch self {
        case .busy: "Cannot retry while dictating."
        case .audioUnavailable: "Cannot retry transcription as audio is no longer available (older than \(DictationLimits.dictationAudioRetentionDays) days)."
        }
    }
}

// MARK: - Updates (UpdateKit; behaviour.md §1.5)

@MainActor
public protocol Updating: AnyObject {
    /// Begins the background schedule (a minute after launch, then every six hours).
    func start()
}

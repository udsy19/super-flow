import Foundation

// Domain model (behaviour.md §2, §6, §8, §11, §19, §20). Everything here is a plain Codable value; the store
// persists it, the modules pass it around. Section numbers in comments refer to behaviour.md unless stated.

// MARK: - Apps and context (§6)

/// What kind of app the user is dictating into; drives Style, formatting rules and the typing reminder (§6.2).
public enum AppCategory: String, Codable, CaseIterable, Sendable {
    case personalMessaging = "personal_messaging"
    case work
    case email
    case document
    case ai
    case terminal
    case other

    /// The Style tab this category uses (§8.4): personal / work / email / other.
    public var styleCategory: StyleCategory {
        switch self {
        case .personalMessaging: .personal
        case .work: .work
        case .email: .email
        case .document, .ai, .terminal, .other: .other
        }
    }
}

/// The frontmost app at dictation start (§6.1).
public struct AppRecord: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    /// The current page for browsers.
    public var url: String?
    public var windowTitle: String?
    public var category: AppCategory

    public init(bundleID: String, name: String, url: String? = nil, windowTitle: String? = nil, category: AppCategory = .other) {
        self.bundleID = bundleID; self.name = name; self.url = url; self.windowTitle = windowTitle; self.category = category
    }
}

/// The focused text element around the caret (§6.3), capped at `AppContext.maxTextboxLength` characters.
public struct AppContext: Codable, Hashable, Sendable {
    public static let maxTextboxLength = 500

    public var app: AppRecord?
    public var textBefore: String
    public var selectedText: String
    public var textAfter: String
    public var isEditable: Bool
    /// False when the focused element is a secure (password) field: nothing is inserted (§9.8).
    public var isSecure: Bool
    /// Words seen in the visible accessibility tree, for vocabulary hints.
    public var nearbyWords: [String]
    /// The Accessibility role of the focused element ("AXTextField", "AXTextArea", "AXWebArea"…); nil when none.
    public var fieldRole: String?

    public init(app: AppRecord? = nil, textBefore: String = "", selectedText: String = "", textAfter: String = "",
                isEditable: Bool = false, isSecure: Bool = false, nearbyWords: [String] = [], fieldRole: String? = nil) {
        self.app = app; self.textBefore = textBefore; self.selectedText = selectedText; self.textAfter = textAfter
        self.isEditable = isEditable; self.isSecure = isSecure; self.nearbyWords = nearbyWords; self.fieldRole = fieldRole
    }

    /// A one-line field (a text field or combo box): Return would send or submit rather than add a line.
    public var isSingleLineField: Bool { fieldRole == "AXTextField" || fieldRole == "AXComboBox" }
}

// MARK: - Dictation (§2)

public enum DictationMode: String, Codable, CaseIterable, Sendable {
    case pushToTalk = "ptt"
    case handsFree = "popo"
    case command = "lens"
}

/// What started a dictation (§2.1).
public enum DictationSource: String, Codable, CaseIterable, Sendable {
    case keyboard, mouse, statusIndicator = "status_indicator", deeplink, error
}

/// The dictation state machine (§2.2).
public enum DictationStatus: String, Codable, CaseIterable, Sendable {
    case idle, initializing, listening, stopping, processing, retrying, error, dismissed, testing

    public var isRecording: Bool { self == .initializing || self == .listening }
    public var isBusy: Bool { [.initializing, .stopping, .processing, .retrying].contains(self) }
    /// A new dictation may start only from here.
    public var canStart: Bool { [.idle, .dismissed, .error].contains(self) }
}

/// Why a dictation was dismissed (§2.2, exact values).
public enum DismissReason: String, Codable, CaseIterable, Sendable {
    case userEscape = "user_action_escape"
    case userCancelButton = "user_action_cancel_button"
    case userSettingsButton = "user_action_settings_button"
    case otherShortcut = "other_shortcut"
    case debouncePushToTalk = "debounce_ptt"
    case debounceHandsFree = "debounce_popo"
    case debounceTriplePress = "debounce_triple_press"
    case longInitialization = "long_initialization"
    case excessiveDuration = "excessive_duration_error"
    case noAudioDuringDictation = "no_audio_during_dictation_error"
    case micAcquisitionFailed = "mic_acquisition_failed"
    case audioContextRecovery = "audio_context_recovery"
    case onboardingExited = "onboarding_exited"
}

/// How a dictation ended up (§2.2 outcomes, `History.status`).
public enum DictationOutcome: String, Codable, CaseIterable, Sendable {
    case empty, error, rawTranscript = "raw_transcript", formatted, fallback, verificationFailed = "verification_failed"
    case noAudio = "no_audio", dismissed, processing, timeout
}

/// Limits and timings of a dictation session (§2.3).
public enum DictationLimits {
    /// Double-tap / debounce window.
    public static let debounceWindow: TimeInterval = 0.5
    /// Scratchpad hold → push-to-talk.
    public static let scratchpadHoldDelay: TimeInterval = 0.35
    public static let maxSessionDuration: TimeInterval = 20 * 60
    public static let sessionWarningAt: TimeInterval = 19 * 60
    /// PTT started less than this ago and another chord begins → dismiss with `otherShortcut`.
    public static let otherShortcutCancelWindow: TimeInterval = 1
    /// Stale-key sweep period and the age past which a held key is dropped (§3.3.8).
    public static let staleKeySweepInterval: TimeInterval = 5
    public static let staleKeyDropAfter: TimeInterval = 10
    public static let staleKeyVerifyAfter: TimeInterval = 2.5
    /// Transform input cap, in words (§10).
    public static let transformMaxWords = 1000
    /// Audio kept for retry and playback (§2.3).
    public static let dictationAudioRetentionDays = 14
    /// Pre-roll kept before the key went down and post-roll after it came up (local-models.md §2.8).
    public static let preRoll: TimeInterval = 0.3
    public static let postRoll: TimeInterval = 0.15
    /// No microphone frame for this long after the start → dismiss with `noAudioDuringDictation`.
    public static let noAudioTimeout: TimeInterval = 3
    /// A dictation shorter than this with no speech is a tap, not a failure: nothing is shown.
    public static let silentTapDuration: TimeInterval = 1.5
    /// LLM wall-time caps (local-models.md §3.6, §4): short utterances, and longer ones whose earlier segments were
    /// already handled while the key was held.
    public static let cleanupBudgetShort: TimeInterval = 1.0
    public static let cleanupBudgetLong: TimeInterval = 2.5
    public static let cleanupShortWords = 12
    /// How long edits to the inserted text are watched for auto-learn (§9.4).
    public static let autoLearnWindow: TimeInterval = 30
    /// How long "Cleaned up!" / "Done." stay on the pill before it rests.
    public static let completedStateDuration: TimeInterval = 2

    public static func cleanupBudget(words: Int) -> TimeInterval { words <= cleanupShortWords ? cleanupBudgetShort : cleanupBudgetLong }
}

/// One dictation in History (§11.1, `History` table §19.1).
public struct Dictation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    /// What the speech engine heard.
    public var rawText: String
    /// After cleanup (same as `rawText` when cleanup was off or fell back).
    public var cleanedText: String
    /// What the user changed the inserted text into, when observed (auto-learn, §8.5).
    public var editedText: String?
    public var app: AppRecord?
    /// BCP-47 of the detected or forced language.
    public var language: String
    /// Seconds of audio.
    public var duration: TimeInterval
    public var wordCount: Int
    public var mode: DictationMode
    public var source: DictationSource
    public var outcome: DictationOutcome
    /// Whether "Undo AI edit" is in effect: the raw transcript is the one in use.
    public var usesRawText: Bool
    /// File name under `SuperFlowPaths.dictationAudio`, nil once pruned.
    public var audioFile: String?
    public var isArchived: Bool

    public init(id: UUID = UUID(), createdAt: Date = Date(), rawText: String, cleanedText: String, editedText: String? = nil,
                app: AppRecord? = nil, language: String = "en", duration: TimeInterval = 0, wordCount: Int? = nil,
                mode: DictationMode = .pushToTalk, source: DictationSource = .keyboard, outcome: DictationOutcome = .formatted,
                usesRawText: Bool = false, audioFile: String? = nil, isArchived: Bool = false) {
        self.id = id; self.createdAt = createdAt; self.rawText = rawText; self.cleanedText = cleanedText
        self.editedText = editedText; self.app = app; self.language = language; self.duration = duration
        self.wordCount = wordCount ?? Dictation.countWords(cleanedText); self.mode = mode; self.source = source
        self.outcome = outcome; self.usesRawText = usesRawText; self.audioFile = audioFile; self.isArchived = isArchived
    }

    /// The text History shows and "Paste last transcript" pastes.
    public var displayText: String { usesRawText ? rawText : cleanedText }

    public static func countWords(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

// MARK: - Dictionary and snippets (§8.5, §8.6)

/// Where a dictionary entry came from.
public enum DictionarySource: String, Codable, CaseIterable, Sendable {
    case manual, learned, imported, starter
}

/// A personal-dictionary word or phrase, optionally with a replacement rule (misspelling → spelling).
public struct DictionaryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var phrase: String
    /// When set, `phrase` is what the engine tends to hear and `replacement` is what should be written.
    public var replacement: String?
    public var isStarred: Bool
    public var source: DictionarySource
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int

    public init(id: UUID = UUID(), phrase: String, replacement: String? = nil, isStarred: Bool = false,
                source: DictionarySource = .manual, createdAt: Date = Date(), lastUsedAt: Date? = nil, useCount: Int = 0) {
        self.id = id; self.phrase = phrase; self.replacement = replacement; self.isStarred = isStarred
        self.source = source; self.createdAt = createdAt; self.lastUsedAt = lastUsedAt; self.useCount = useCount
    }
}

/// A spoken trigger that expands to a longer text, applied deterministically after cleanup (§8.6).
public struct Snippet: Codable, Hashable, Identifiable, Sendable {
    public static let maxExpansionLength = 2000

    public var id: UUID
    public var trigger: String
    public var expansion: String
    public var createdAt: Date
    public var useCount: Int

    public init(id: UUID = UUID(), trigger: String, expansion: String, createdAt: Date = Date(), useCount: Int = 0) {
        self.id = id; self.trigger = trigger; self.expansion = expansion; self.createdAt = createdAt; self.useCount = useCount
    }
}

// MARK: - Notes (§11.4)

/// A Notes page entry: quick notes and drafts the user dictates into (the Scratchpad without the floating window).
public struct ScratchNote: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// The first non-empty line, or "New note".
    public var title: String {
        text.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "New note"
    }

    /// The text after the title line, flattened to one line.
    public var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " ")
    }
}

// MARK: - Style (§8.2, §8.4)

public enum StyleCategory: String, Codable, CaseIterable, Sendable {
    case personal, work, email, other
}

/// Writing style per category (local-models.md §1.1 `WritingStyle`).
public enum WritingStyle: String, Codable, CaseIterable, Sendable {
    case formal, casual, veryCasual = "very_casual", excited

    /// Which styles a category offers (§8.4).
    public static func options(for category: StyleCategory) -> [WritingStyle] {
        category == .personal ? [.formal, .casual, .veryCasual] : [.formal, .casual, .excited]
    }
}

/// Auto-cleanup level (§8.2); `none` skips the LLM entirely (rules only).
public enum CleanupLevel: String, Codable, CaseIterable, Sendable {
    case none, light, medium, high
}

/// Per-app transcription format (§8.4, right-click › Formatting options).
public enum TranscriptionFormat: String, Codable, CaseIterable, Sendable {
    case aiFormatting = "Apply AI formatting"
    case noAIFormatting = "No AI formatting"
    case casualMessaging = "Casual messaging"
    case allLowercase = "All lowercase"
}

/// The user's Style settings: one writing style per category plus the cleanup level (§22.4.3 defaults: Casual for
/// personal, Formal elsewhere).
public struct StyleProfile: Codable, Hashable, Sendable {
    public var styles: [StyleCategory: WritingStyle]
    public var cleanupLevel: CleanupLevel

    public init(styles: [StyleCategory: WritingStyle] = StyleProfile.defaultStyles, cleanupLevel: CleanupLevel = .light) {
        self.styles = styles; self.cleanupLevel = cleanupLevel
    }

    public static let defaultStyles: [StyleCategory: WritingStyle] = [.personal: .casual, .work: .formal, .email: .formal, .other: .formal]
    public static let `default` = StyleProfile()

    public func style(for category: StyleCategory) -> WritingStyle { styles[category] ?? StyleProfile.defaultStyles[category] ?? .formal }
}

// MARK: - Transforms and Command Mode (§10)

/// A saved rewrite prompt ("Polish", custom ones) applied to selected text.
public struct TransformPrompt: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var instruction: String
    /// Key chord that runs it, nil for none.
    public var shortcut: KeyChord?
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, instruction: String, shortcut: KeyChord? = nil, isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.instruction = instruction; self.shortcut = shortcut; self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Audio and transcripts (local-models.md §8.2, §9.1)

/// 16 kHz mono Float32 samples, the only audio format the pipeline passes around.
public struct AudioClip: Sendable {
    public static let sampleRate = 16_000

    public var samples: [Float]
    /// Host time of the first sample, for interleaving channels.
    public var startTime: TimeInterval

    public init(samples: [Float], startTime: TimeInterval = 0) {
        self.samples = samples; self.startTime = startTime
    }

    public var duration: TimeInterval { Double(samples.count) / Double(AudioClip.sampleRate) }
}

/// Which capture the audio came from: the user's microphone ("You") or the Mac's output ("Them") (§20.4).
public enum AudioChannel: String, Codable, CaseIterable, Sendable {
    case mic, system

    public var liveLabel: String { self == .mic ? "You" : "Them" }
}

/// One stretch of recognised speech with timestamps relative to the recording start.
public struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var channel: AudioChannel
    public var speakerID: UUID?
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    /// False for a streaming partial that a later segment replaces.
    public var isFinal: Bool

    public init(id: UUID = UUID(), channel: AudioChannel = .mic, speakerID: UUID? = nil, start: TimeInterval, end: TimeInterval,
                text: String, isFinal: Bool = true) {
        self.id = id; self.channel = channel; self.speakerID = speakerID; self.start = start; self.end = end
        self.text = text; self.isFinal = isFinal
    }
}

/// A finished recognition of one clip.
public struct Transcript: Codable, Hashable, Sendable {
    public var text: String
    /// BCP-47 detected or forced language.
    public var language: String
    /// 0…1; `languageConfidence` below 0.5 means "Speaking a different language?" (local-models.md §2.10).
    public var confidence: Double
    public var languageConfidence: Double
    public var segments: [TranscriptSegment]

    public init(text: String, language: String = "en", confidence: Double = 1, languageConfidence: Double = 1,
                segments: [TranscriptSegment] = []) {
        self.text = text; self.language = language; self.confidence = confidence
        self.languageConfidence = languageConfidence; self.segments = segments
    }
}

/// Dictation pre-empts meeting work on the shared engines (local-models.md §8.3).
public enum SpeechPriority: Int, Codable, Sendable, Comparable {
    case meeting = 0, dictation = 1
    public static func < (a: SpeechPriority, b: SpeechPriority) -> Bool { a.rawValue < b.rawValue }
}

public struct TranscriptionOptions: Codable, Hashable, Sendable {
    /// Languages the user selected; empty means auto-detect among everything the engine knows.
    public var languages: [String]
    /// Spellings to keep (starred dictionary first, then the rest, then app-context words), capped by the engine.
    public var vocabulary: [String]
    /// The previous dictation's text, for continuity.
    public var previousText: String?
    /// The channel the audio comes from; segments of an incremental transcription carry it.
    public var channel: AudioChannel

    public init(languages: [String] = [], vocabulary: [String] = [], previousText: String? = nil, channel: AudioChannel = .mic) {
        self.languages = languages; self.vocabulary = vocabulary; self.previousText = previousText; self.channel = channel
    }
}

/// What a streaming recogniser emits while audio is still arriving.
public enum TranscriptionEvent: Sendable {
    /// Live partial text that later events replace.
    case partial(String)
    /// A closed segment that will not change.
    case segment(TranscriptSegment)
    /// The whole utterance, after the stream was finished.
    case final(Transcript)
}

// MARK: - Meetings (§20)

public enum MeetingPlatform: String, Codable, CaseIterable, Sendable {
    case zoom, teams, googleMeet = "google_meet", slack, webex, discord, whatsapp, facetime, other
}

public struct Participant: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var email: String?

    public init(id: UUID = UUID(), name: String, email: String? = nil) {
        self.id = id; self.name = name; self.email = email
    }
}

/// A voice the diarizer found; the user names it ("Update everywhere", §20.7.3).
public struct Speaker: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// "Speaker 1", "You", "Them"…
    public var label: String
    /// The person's name once assigned.
    public var name: String?
    public var channel: AudioChannel

    public init(id: UUID = UUID(), label: String, name: String? = nil, channel: AudioChannel = .system) {
        self.id = id; self.label = label; self.name = name; self.channel = channel
    }

    public var displayName: String { name ?? label }
}

/// One recorded channel of a meeting (§20.4.6).
public struct AudioTrack: Codable, Hashable, Sendable {
    public var channel: AudioChannel
    /// File name under `SuperFlowPaths.meetingAudio(meetingID)`.
    public var file: String
    public var duration: TimeInterval
    public var byteSize: Int

    public init(channel: AudioChannel, file: String, duration: TimeInterval = 0, byteSize: Int = 0) {
        self.channel = channel; self.file = file; self.duration = duration; self.byteSize = byteSize
    }
}

public struct ActionItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var meetingID: UUID?
    public var text: String
    public var owner: String?
    public var due: Date?
    public var isCompleted: Bool
    public var isArchived: Bool
    public var sortOrder: Int

    public init(id: UUID = UUID(), meetingID: UUID? = nil, text: String, owner: String? = nil, due: Date? = nil,
                isCompleted: Bool = false, isArchived: Bool = false, sortOrder: Int = 0) {
        self.id = id; self.meetingID = meetingID; self.text = text; self.owner = owner; self.due = due
        self.isCompleted = isCompleted; self.isArchived = isArchived; self.sortOrder = sortOrder
    }
}

/// The notes the summarizer writes (§20.7.5 template).
public struct MeetingSummary: Codable, Hashable, Sendable {
    /// Below this many words of transcript plus notes there is nothing worth summarising.
    public static let minimumWords = 25

    public var title: String
    public var summary: String
    public var decisions: [String]
    public var actionItems: [ActionItem]
    public var followUps: [String]
    public var generatedAt: Date
    /// `ModelDescriptor.id` of the model that wrote it.
    public var modelID: String

    public init(title: String, summary: String, decisions: [String] = [], actionItems: [ActionItem] = [], followUps: [String] = [],
                generatedAt: Date = Date(), modelID: String = "") {
        self.title = title; self.summary = summary; self.decisions = decisions; self.actionItems = actionItems
        self.followUps = followUps; self.generatedAt = generatedAt; self.modelID = modelID
    }
}

/// A moment the user marked while recording ("Pricing", or just a bookmark), seconds into the meeting.
public struct MeetingMarker: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var time: TimeInterval
    public var label: String

    public init(id: UUID = UUID(), time: TimeInterval, label: String = "") {
        self.id = id; self.time = time; self.label = label
    }

    /// "12:04" or "1:02:30".
    public var timestamp: String { MeetingMarker.timestamp(time) }

    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
                             : String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// A recorded meeting (§19.1 `Meetings`, §20).
public struct Meeting: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var platform: MeetingPlatform
    /// EventKit identifier of the matching calendar event, when any.
    public var calendarEventID: String?
    public var participants: [Participant]
    public var speakers: [Speaker]
    public var tracks: [AudioTrack]
    public var segments: [TranscriptSegment]
    /// The user's own notes, kept verbatim.
    public var notes: String
    /// Moments marked while recording, in time order.
    public var markers: [MeetingMarker]
    public var summary: MeetingSummary?
    /// Set when the audio files were deleted by retention or by the user; transcript and notes stay.
    public var audioDeletedAt: Date?
    public var folder: String?

    public init(id: UUID = UUID(), title: String, startedAt: Date = Date(), endedAt: Date? = nil, platform: MeetingPlatform = .other,
                calendarEventID: String? = nil, participants: [Participant] = [], speakers: [Speaker] = [], tracks: [AudioTrack] = [],
                segments: [TranscriptSegment] = [], notes: String = "", markers: [MeetingMarker] = [], summary: MeetingSummary? = nil,
                audioDeletedAt: Date? = nil, folder: String? = nil) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.endedAt = endedAt; self.platform = platform
        self.calendarEventID = calendarEventID; self.participants = participants; self.speakers = speakers; self.tracks = tracks
        self.segments = segments; self.notes = notes; self.markers = markers; self.summary = summary
        self.audioDeletedAt = audioDeletedAt; self.folder = folder
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startedAt, endedAt, platform, calendarEventID, participants, speakers, tracks, segments, notes, markers, summary
        case audioDeletedAt, folder
    }

    /// Rows written before markers existed decode with none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        platform = try c.decode(MeetingPlatform.self, forKey: .platform)
        calendarEventID = try c.decodeIfPresent(String.self, forKey: .calendarEventID)
        participants = try c.decode([Participant].self, forKey: .participants)
        speakers = try c.decode([Speaker].self, forKey: .speakers)
        tracks = try c.decode([AudioTrack].self, forKey: .tracks)
        segments = try c.decode([TranscriptSegment].self, forKey: .segments)
        notes = try c.decode(String.self, forKey: .notes)
        markers = try c.decodeIfPresent([MeetingMarker].self, forKey: .markers) ?? []
        summary = try c.decodeIfPresent(MeetingSummary.self, forKey: .summary)
        audioDeletedAt = try c.decodeIfPresent(Date.self, forKey: .audioDeletedAt)
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
    }

    public var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
    public var hasAudio: Bool { !tracks.isEmpty && audioDeletedAt == nil }
    /// Something was transcribed; without it the audio is the meeting's only record.
    public var hasTranscript: Bool { !MeetingExport.finalSegments(segments).isEmpty }
    public var transcriptText: String {
        segments.filter(\.isFinal).map { "\(speakerLabel(for: $0)): \($0.text)" }.joined(separator: "\n")
    }

    public func speakerLabel(for segment: TranscriptSegment) -> String {
        if let id = segment.speakerID, let speaker = speakers.first(where: { $0.id == id }) { return speaker.displayName }
        return segment.channel.liveLabel
    }
}

/// A calendar event that looks like a meeting (§20.10), mirrored from EventKit.
public struct CalendarEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var attendees: [Participant]
    public var joinURL: URL?
    public var platform: MeetingPlatform?

    public init(id: String, title: String, start: Date, end: Date, attendees: [Participant] = [], joinURL: URL? = nil,
                platform: MeetingPlatform? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.attendees = attendees
        self.joinURL = joinURL; self.platform = platform
    }
}

// MARK: - Models (local-models.md §5)

public enum ModelKind: String, Codable, CaseIterable, Sendable {
    case asr, llm, vad, diarization, coremlEncoder = "coreml-encoder", echoCancel = "echo-cancel"
}

/// A downloadable model in the compiled-in catalog (local-models.md §5.2).
public struct ModelDescriptor: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: ModelKind
    public var name: String
    /// Which engine loads it: "whisper", "llama", "fluidaudio", "fluidaudio-nemotron", or "apple" (part of macOS 26,
    /// nothing to download).
    public var engine: String
    public var bytes: Int64
    /// Pinned download URL (a Hugging Face `resolve/<revision>/` URL); nil for Core ML sets FluidAudio fetches itself.
    public var url: URL?
    /// Lower-case hex; nil when the set is a folder of files FluidAudio verifies by revision.
    public var sha256: String?
    /// Hugging Face repo and revision for Core ML folders.
    public var repository: String?
    public var revision: String?
    /// The folder of `repository` that holds the set, when the repository has several ("nemotron_coreml_1120ms"); its
    /// files install without the prefix.
    public var subfolder: String?
    public var licence: String
    /// Text shown in About › Licences (CC-BY attribution, "Built with…").
    public var attribution: String
    /// BCP-47 codes, or ["auto"] when the model detects languages.
    public var languages: [String]
    /// Bytes of RAM the model needs while loaded.
    public var minRAM: Int64

    public init(id: String, kind: ModelKind, name: String, engine: String, bytes: Int64, url: URL? = nil, sha256: String? = nil,
                repository: String? = nil, revision: String? = nil, subfolder: String? = nil, licence: String, attribution: String = "",
                languages: [String] = ["auto"], minRAM: Int64 = 0) {
        self.id = id; self.kind = kind; self.name = name; self.engine = engine; self.bytes = bytes; self.url = url; self.sha256 = sha256
        self.repository = repository; self.revision = revision; self.subfolder = subfolder; self.licence = licence
        self.attribution = attribution; self.languages = languages; self.minRAM = minRAM
    }

    /// Part of the OS: never downloaded, never listed as a download.
    public var isBuiltIn: Bool { engine == "apple" }

    /// The file or folder name under `SuperFlowPaths.models(kind)`.
    public var fileName: String { url?.lastPathComponent ?? id }
}

public enum ModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(fraction: Double)
    case paused(fraction: Double)
    case installed
    case damaged
}

public struct DownloadProgress: Equatable, Sendable {
    public var bytesReceived: Int64
    public var bytesExpected: Int64
    /// Bytes per second over the last few seconds.
    public var rate: Double
    public var fraction: Double { bytesExpected > 0 ? Double(bytesReceived) / Double(bytesExpected) : 0 }
    public var estimatedTimeRemaining: TimeInterval? { rate > 0 ? Double(bytesExpected - bytesReceived) / rate : nil }

    public init(bytesReceived: Int64, bytesExpected: Int64, rate: Double = 0) {
        self.bytesReceived = bytesReceived; self.bytesExpected = bytesExpected; self.rate = rate
    }
}

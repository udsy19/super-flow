import Foundation

// Every user setting (behaviour.md §13, §19.2, §20.11 and the owner decisions), grouped by Settings pane. Key names
// follow the reference app's where it has one, so the spec maps one to one. State private to a module (change
// tokens, caches) is declared in that module with the module name as prefix ("updateKit.lastAttempt").

/// Settings › Data and Privacy › Local data storage (§11.2).
public enum LocalDataPolicy: String, Codable, CaseIterable, Sendable {
    case store = "StoreNormally"
    case autoDelete24h = "AutoDelete24h"
    case never = "NeverStore"
}

/// Settings › Notetaker › Meeting detection (§13.6).
public enum MeetingDetectionPolicy: String, Codable, CaseIterable, Sendable {
    case notify, doNothing
}

/// Notify before scheduled meetings start (§13.6): never, right before (15 s), 1 minute, 2 minutes.
public enum MeetingReminderLead: Int, Codable, CaseIterable, Sendable {
    case never = -1, rightBefore = 15, oneMinute = 60, twoMinutes = 120
}

/// Typing reminder scope (§5.7).
public enum TypingReminderScope: String, Codable, CaseIterable, Sendable {
    case disabled, allApps, aiApps, documents, email, personalMessaging, workMessaging, specificApps
}

/// Scratchpad open behaviour (§11.4).
public enum ScratchpadOpenBehavior: String, Codable, CaseIterable, Sendable {
    case `default`, alwaysNewTab, lastActivePinned
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case light, dark, system
}

public extension Defaults.Keys {
    // MARK: General (§13.1)

    static let shortcuts = Key<ShortcutMap>("shortcuts", default: .macDefaults)
    /// BCP-47 codes; the UI locale's language until changed. Empty with `autoDetectLanguage` on means all 99.
    static let selectedLanguages = Key<[String]>("selectedLanguages", default: [Locale.current.language.languageCode?.identifier ?? "en"])
    static let autoDetectLanguage = Key<Bool>("autoDetectLanguage", default: false)
    /// Explicit microphone (`AudioDevice.id`), nil for the ranked list / built-in.
    static let overrideAudioDeviceId = Key<String?>("overrideAudioDeviceId", default: nil)
    /// User-ordered microphone preference (`AudioDevice.id`s).
    static let rankedAudioDevices = Key<[String]>("rankedAudioDevices", default: [])

    // MARK: System (§13.2)

    /// Mirrors the login item (SMAppService).
    static let openAtLogin = Key<Bool>("openAtLogin", default: true)
    /// "Show Flow Bar at all times" (inverted storage as in the reference).
    static let hideFlowBarPermanently = Key<Bool>("hideFlowBarPermanently", default: false)
    static let flowBarEdge = Key<FlowBarEdge>("statusDockEdge", default: .bottom)
    /// "Hide for 1 hour": seconds since 1970 until which the resting bar stays hidden.
    static let flowBarHiddenUntil = Key<Double>("flowBarHiddenUntil", default: 0)
    static let typingReminderScope = Key<TypingReminderScope>("typingReminderScope", default: .disabled)
    static let typingReminderApps = Key<[String]>("typingReminderApps", default: [])
    /// Owner decision: Super Flow is a Dock app. The toggle is kept for users who prefer an agent app.
    static let hideAppInDock = Key<Bool>("hideAppInDock", default: false)
    static let shouldAutoLearnWords = Key<Bool>("shouldAutoLearnWords", default: true)
    /// Shows "Dictating with Super Flow" while dictating (screen recordings).
    static let creatorMode = Key<Bool>("creatorMode", default: false)
    static let enableSounds = Key<Bool>("enableSounds", default: true)
    static let shouldMuteAudio = Key<Bool>("shouldMuteAudio", default: false)
    static let notifySuggestions = Key<Bool>("notifySuggestions", default: true)
    static let notifyAnnouncements = Key<Bool>("notifyAnnouncements", default: true)
    static let notifyMilestones = Key<Bool>("notifyMilestones", default: true)
    static let scratchpadOpenBehavior = Key<ScratchpadOpenBehavior>("scratchpadOpenBehavior", default: .default)
    static let scratchpadInFlowBar = Key<Bool>("scratchpadInFlowBar", default: false)
    static let theme = Key<AppTheme>("theme", default: .light)
    static let processingDelayNotificationEnabled = Key<Bool>("processingDelayNotificationEnabled", default: true)

    // MARK: Style and formatting (§8.2, §8.4)

    static let styleProfile = Key<StyleProfile>("personalizationStyles", default: .default)
    static let styleDetectionEnabled = Key<Bool>("styleDetectionEnabled", default: true)
    static let defaultTranscriptionFormat = Key<TranscriptionFormat>("defaultTranscriptionFormat", default: .aiFormatting)
    /// Per-app overrides: bundle id → format.
    static let appTranscriptionFormats = Key<[String: TranscriptionFormat]>("appTranscriptionFormats", default: [:])
    static let dictionarySort = Key<String>("dictionarySort", default: "Newest")

    // MARK: Transforms (§10)

    static let polishEnabled = Key<Bool>("polishEnabled", default: true)
    static let polishAutoPaste = Key<Bool>("polishAutoPaste", default: true)
    /// Run this transform (`TransformPrompt.id`) after every dictation; nil = off.
    static let autoPolishAfterDictation = Key<String?>("autoPolishAfterDictation", default: nil)
    /// Polish rule checkboxes (§10.1), on by default.
    static let polishRules = Key<[String]>("polishRules", default: ["concise", "clarity", "reorder", "structure", "tone"])

    // MARK: Vibe coding (§13.3)

    static let cursorIdeIntegration = Key<Bool>("cursorIdeIntegration", default: false)
    static let ideFileTagging = Key<Bool>("ideFileTagging", default: true)

    // MARK: Experimental (§13.4)

    static let commandModeEnabled = Key<Bool>("commandModeEnabled", default: false)
    static let pressEnterCommandEnabled = Key<Bool>("pressEnterCommandEnabled", default: false)
    static let stackedMessagesEnabled = Key<Bool>("stackedMessagesEnabled", default: false)
    static let shouldPauseAudio = Key<Bool>("shouldPauseAudio", default: false)
    static let focusModeEnabled = Key<Bool>("focusModeEnabled", default: false)
    static let focusModeBlockedApps = Key<[String]>("focusModeBlockedApps", default: [])
    static let focusModeBlockedURLs = Key<[String]>("focusModeBlockedURLs", default: [])

    // MARK: Data and Privacy (§13.5)

    /// "Context awareness": read the focused text field for spelling and continuation.
    static let useAxContext = Key<Bool>("useAxContext", default: true)
    static let localDataPolicy = Key<LocalDataPolicy>("localDataPolicy", default: .store)
    /// Notetaker transcript retention in days; 0 = never delete (§13.5).
    static let meetingTranscriptRetentionDays = Key<Int>("notetakerTranscriptRetention", default: RetentionPolicy.keepForever)
    /// Owner decision: meeting audio is kept 30 days then deleted; transcripts and notes stay.
    static let meetingAudioRetentionDays = Key<Int>("meetingAudioRetentionDays", default: 30)

    // MARK: Insertion (§9)

    static let insertionMethod = Key<InsertionMethod>("insertionMethod", default: .paste)
    static let restoreClipboardAfterPaste = Key<Bool>("restoreClipboardAfterPaste", default: true)

    // MARK: Models (local-models.md §5.5)

    /// `ModelDescriptor.id` of the dictation engine, the multilingual fallback, the cleanup LLM and the notes LLM.
    static let asrModelID = Key<String>("asrModelID", default: ModelCatalog.parakeetV3.id)
    static let fallbackASRModelID = Key<String>("fallbackASRModelID", default: ModelCatalog.whisperLargeV3Turbo.id)
    /// nil = rules only.
    static let cleanupModelID = Key<String?>("cleanupModelID", default: ModelCatalog.qwen35_2B.id)
    static let notesModelID = Key<String>("notesModelID", default: ModelCatalog.qwen35_4B.id)
    /// Use Apple's on-device engines on macOS 26 when available (SpeechTranscriber, Foundation Models).
    static let useAppleSpeech = Key<Bool>("useAppleSpeech", default: false)
    static let useAppleIntelligence = Key<Bool>("useAppleIntelligence", default: false)
    /// Owner decision: models download automatically in the background after install (`AutoDownloadPolicy`).
    static let autoDownloadModels = Key<Bool>("autoDownloadModels", default: true)
    /// When the disk check last refused to download, in seconds since 1970 (0 = never); retried daily.
    static let autoDownloadDiskRetryAfter = Key<Double>("autoDownloadDiskRetryAfter", default: 0)
    /// Keep models resident between dictations (on by default on ≥ 16 GB Macs; the Models pane sets it at first run).
    static let keepModelsInMemory = Key<Bool>("keepModelsInMemory", default: true)
    /// Base URL for model downloads; "" = Hugging Face.
    static let modelMirrorURL = Key<String>("modelMirrorURL", default: "")

    // MARK: Notetaker (§13.6, §20.11)

    static let meetingDetection = Key<MeetingDetectionPolicy>("autoDetectMeetings", default: .notify)
    /// Owner decision: a detected meeting always asks "Meeting detected — Record?"; auto-start stays off.
    static let notetakerAutoStartEnabled = Key<Bool>("notetakerAutoStartEnabled", default: false)
    static let notetakerAutoEndEnabled = Key<Bool>("notetakerAutoEndEnabled", default: true)
    static let meetingReminderLead = Key<MeetingReminderLead>("notetakerCalendarNotificationLead", default: .oneMinute)
    static let notetakerCalendarNotificationsEnabled = Key<Bool>("notetakerCalendarNotificationsEnabled", default: true)
    static let notetakerLiveTranscriptEnabled = Key<Bool>("notetakerLiveTranscriptEnabled", default: true)
    static let notetakerAttributeNamesEnabled = Key<Bool>("notetakerAttributeNamesEnabled", default: true)
    static let notetakerAutoDetectParticipantNamesEnabled = Key<Bool>("notetakerAutoDetectParticipantNamesEnabled", default: true)
    /// Seconds; options 30 min / 1 h / 2 h / 3 h.
    static let notetakerMaxRecordingLength = Key<Int>("notetakerMaxRecordingLength", default: 2 * 3600)
    static let notetakerLongMeetingCheckInEnabled = Key<Bool>("notetakerLongMeetingCheckInEnabled", default: true)
    static let notetakerOpenWindowOnRecord = Key<Bool>("notetakerOpenWindowOnRecord", default: true)
    static let notetakerSplitScreenJoinEnabled = Key<Bool>("notetakerSplitScreenJoinEnabled", default: false)
    static let notetakerTripleTapShortcutEnabled = Key<Bool>("notetakerTripleTapShortcutEnabled", default: true)
    static let notetakerConsentChatEnabled = Key<Bool>("notetakerConsentChatEnabled", default: false)
    static let notetakerConsentMessage = Key<String>("notetakerConsentMessage",
        default: "Hi everyone — quick note that I'm using a local notetaker to transcribe this meeting so I can stay present. Let me know if you'd like me to turn it off.")
    static let hideMeetingRecorderInScreenShare = Key<Bool>("hideMeetingRecorderInScreenShare", default: false)
    static let notetakerMicDeviceId = Key<String?>("notetakerMicDeviceId", default: nil)
    static let calendarAccessRequested = Key<Bool>("calendarAccessRequested", default: false)

    // MARK: Updates

    /// Checks GitHub Releases in the background and installs newer versions (UpdateKit).
    static let installUpdates = Key<Bool>("installUpdates", default: true)
    /// When UpdateKit last reached GitHub Releases, in seconds since 1970 (0 = never).
    static let lastUpdateCheck = Key<Double>("lastUpdateCheck", default: 0)

    // MARK: App state

    static let isOnboardingCompleted = Key<Bool>("isOnboardingCompleted", default: false)
    static let defaultDictionaryItemsLoaded = Key<Bool>("defaultDictionaryItemsLoaded", default: false)
    /// Ids of one-time prompts already shown ("Using Command Mode (beta)", press-enter explanation…).
    static let shownPrompts = Key<Set<String>>("shownPrompts", default: [])
    /// Ids of confirmations the user ticked "Don't ask again" on (`Alerts.confirm`).
    static let suppressedWarnings = Key<Set<String>>("suppressedWarnings", default: [])
    static let userFirstName = Key<String>("userFirstName", default: "")
    static let userLastName = Key<String>("userLastName", default: "")
}

/// Choices the Settings panes offer.
public enum SettingsOptions {
    public static let transcriptRetentionDays = [RetentionPolicy.keepForever, 1, 7, 30, 90, 180, 365]
    public static let meetingAudioRetentionDays = [1, 7, 30, 90, 365, RetentionPolicy.keepForever]
    public static let maxRecordingLengths = [30 * 60, 3600, 2 * 3600, 3 * 3600]
}

import AppKit
import Combine
import Carbon.HIToolbox
import Foundation
import SuperFlowCore
import FlowStore
import SpeechKit
import CleanupKit
import MeetingKit
import DictationKit
import HubKit

// Owned with DictationKit: the hotkey router and auto-learn as pure logic, then the real pipeline end to end with no
// microphone, keyboard or screen: synthetic speech (`say -o`, never played) through a fake capture → the real speech
// engines (dev models) → the real cleanup model → a fake inserter writing to a private named pasteboard → the real
// SQLite history; Command Mode on a selection; the Fn+Space gestures; and a two-track meeting through MeetingKit with
// the notes model. The real-model parts run only with `SUPERFLOW_DEV_MODELS`.
func registerEndToEndTests() {
    SelfTest.cases.append(("E2E.hotkeyRouter", { endToEndRouter() }))
    SelfTest.cases.append(("E2E.autoLearn", { endToEndAutoLearn() }))
    SelfTest.cases.append(("E2E.coordinatorWithFakes", { MainActor.assumeIsolated { endToEndCoordinatorFakes() } }))
    SelfTest.cases.append(("E2E.wordsSurviveFailures", { MainActor.assumeIsolated { endToEndWordsSurviveFailures() } }))
    SelfTest.cases.append(("E2E.killedMidDictation", { MainActor.assumeIsolated { endToEndKilledMidDictation() } }))
    SelfTest.cases.append(("E2E.cleanupModelOnDemand", { MainActor.assumeIsolated { endToEndCleanupModelOnDemand() } }))
    SelfTest.cases.append(("E2E.historyUnavailable", { MainActor.assumeIsolated { endToEndHistoryUnavailable() } }))
    SelfTest.cases.append(("E2E.dictationPipeline", { MainActor.assumeIsolated { endToEndDictation() } }))
    SelfTest.cases.append(("E2E.meetingPipeline", { MainActor.assumeIsolated { endToEndMeeting() } }))
}

private let fnChord = KeyChord(KeyChord.fn)
private let fnSpace = KeyChord(KeyChord.fn, UInt16(kVK_Space))
private let fnCtrl = KeyChord(KeyChord.fn, UInt16(kVK_Control))
private let e2eT0 = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: - Router

private func endToEndRouter() {
    typealias S = HotkeyRouter.State
    func route(_ event: HotkeyEvent, _ state: S, after: TimeInterval = 0) -> HotkeyRouter.Intent {
        HotkeyRouter.route(event, state: state, now: e2eT0.addingTimeInterval(after))
    }
    let idle = S(status: .idle)
    check(route(.pressed(.pushToTalk, fnChord), idle) == .start(.pushToTalk), "Fn down starts push-to-talk")
    check(route(.released(.pushToTalk, fnChord), idle) == .none, "a release while idle is nothing")
    let ptt = S(status: .listening, mode: .pushToTalk, startedAt: e2eT0)
    check(route(.released(.pushToTalk, fnChord), ptt) == .finish, "Fn up finishes push-to-talk")
    check(route(.pressed(.pushToTalk, fnChord), ptt) == .none, "a repeated press is ignored")
    check(route(.pressed(.handsFree, fnSpace), ptt, after: 0.2) == .switchMode(.handsFree), "Fn then Space: the session becomes hands-free")
    check(route(.doubleTap, ptt) == .switchMode(.handsFree), "double tap while holding locks too")
    check(route(.pressed(.commandMode, fnCtrl), S(status: .listening, mode: .pushToTalk, startedAt: e2eT0, commandModeEnabled: true)) == .switchMode(.command),
          "Fn then Control: the session becomes Command Mode")
    check(route(.pressed(.commandMode, fnCtrl), ptt) == .commandModeOff, "Command Mode off: a card, not a mode")
    check(route(.otherKey(during: .pushToTalk, fnChord), ptt, after: 0.5) == .dismiss(.otherShortcut), "another key inside a second cancels")
    check(route(.otherKey(during: .pushToTalk, fnChord), ptt, after: 1.5) == .none, "later on, other keys are ignored")
    let locked = S(status: .listening, mode: .handsFree, startedAt: e2eT0)
    check(route(.pressed(.pushToTalk, fnChord), locked) == .finish && route(.pressed(.handsFree, fnSpace), locked) == .finish
              && route(.doubleTap, locked) == .finish, "push-to-talk, hands-free or a double tap finish a locked session")
    check(route(.released(.pushToTalk, fnChord), locked) == .none, "Fn up does not end a locked session")
    check(route(.tripleTap, locked) == .none && route(.tripleTap, idle) == .notetaker, "triple tap is the Notetaker unless locked")
    check(route(.tripleTap, S(status: .idle, tripleTapEnabled: false)) == .none, "triple tap can be turned off")
    // Stop with Fn+Space: the PTT press finished; the hands-free press that follows lands on a busy or just-finished session.
    let busy = S(status: .processing, lastFinishAt: e2eT0)
    check(route(.pressed(.handsFree, fnSpace), busy, after: 0.05) == .none, "the duplicate press on a busy session is ignored")
    let justDone = S(status: .idle, lastFinishAt: e2eT0)
    check(route(.pressed(.handsFree, fnSpace), justDone, after: 0.3) == .none && route(.pressed(.handsFree, fnSpace), justDone, after: 0.6) == .start(.handsFree),
          "and inside the debounce window after a fast finish")
    check(route(.pressed(.dismiss, KeyChord(UInt16(kVK_Escape))), ptt) == .dismiss(.userEscape) && route(.pressed(.dismiss, KeyChord(UInt16(kVK_Escape))), idle) == .closeCards,
          "Esc cancels a dictation, else closes cards")
    check(route(.released(.pasteLastText, KeyChord(1, 2)), idle) == .pasteLast && route(.pressed(.pasteLastText, KeyChord(1, 2)), idle) == .none,
          "paste-last fires on release")
    check(route(.pressed(.transform, KeyChord(1)), idle) == .transform(.transform) && route(.pressed(.transform, KeyChord(1)), S(status: .idle, transformsEnabled: false)) == .none,
          "transform shortcut honours the setting")
    check(route(.secureInput(blocked: true, ownerBundleID: "x"), ptt) == .secureInput(blocked: true, ownerBundleID: "x"), "secure input is passed on")
}

// MARK: - Auto-learn

private func endToEndAutoLearn() {
    let learned = AutoLearn.entries(cleaned: "Send the kubernetes upgrade notes to anais today.", edited: "Send the Kubernetes upgrade notes to Anaïs today.", known: [])
    check(learned.map { "\($0.phrase)→\($0.replacement ?? "")" } == ["kubernetes→Kubernetes", "anais→Anaïs"], "capitals and accents become replacements: \(learned)")
    check(learned.allSatisfy { $0.source == .learned }, "marked as learned")
    let typo = AutoLearn.entries(cleaned: "Ping Jon about the Febuary numbers.", edited: "Ping Jon about the February numbers.", known: [])
    check(typo.map(\.phrase) == ["Febuary"] && typo.first?.replacement == "February", "a close spelling is a correction")
    let inserted = AutoLearn.entries(cleaned: "Ask about the release.", edited: "Ask Priya about the release.", known: [])
    check(inserted.map(\.phrase) == ["Priya"] && inserted.first?.replacement == nil, "a typed-in name is a plain entry")
    check(AutoLearn.entries(cleaned: "Ask about the release.", edited: "Ask about the release", known: []).isEmpty, "punctuation-only edits teach nothing")
    check(AutoLearn.entries(cleaned: "We will ship it.", edited: "We won't ship it.", known: []).isEmpty, "everyday words are never learned")
    check(AutoLearn.entries(cleaned: "the whole sentence", edited: "something else entirely here", known: []).isEmpty, "a rewrite is not a correction")
    let known = [DictionaryEntry(phrase: "anais", replacement: "Anaïs")]
    check(AutoLearn.entries(cleaned: "tell anais", edited: "tell Anaïs", known: known).isEmpty, "known entries are not added again")
    check(AutoLearn.diff(["a", "b", "c"], ["a", "x", "c"]) == [.substitution(heard: "b", written: "x")], "word diff pairs substitutions")
}

// MARK: - Fakes

@MainActor private final class E2EHotkeys: HotkeyMonitoring {
    let events: AsyncStream<HotkeyEvent>
    let recorderEvents: AsyncStream<KeyChord>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    var isRunning = true
    var tapMode: HotkeyTapMode? { .active }
    var isRecording = false
    var hasFnKey: Bool { true }
    init() {
        (events, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        recorderEvents = AsyncStream { $0.finish() }
    }
    func start() throws {}
    func stop() {}
    func update(_ map: ShortcutMap) {}
    func send(_ event: HotkeyEvent) { continuation.yield(event) }
}

@MainActor private final class E2EAudio: AudioCapturing {
    var devices: [AudioDevice] = [AudioDevice(id: "fake", name: "Fake microphone", isBuiltIn: true)]
    var selectedDevice: AudioDevice? { devices.first }
    var holders = 0
    var isCapturingMicrophone: Bool { holders > 0 }
    var isCapturingSystemAudio = false
    var systemAudioMethod: SystemAudioMethod { .processTap }
    var cues: [SoundCue] = []
    var muted = 0
    var clock: TimeInterval = 1000
    private var subscribers: [UUID: AsyncStream<AudioFrame>.Continuation] = [:]
    var frames: AsyncStream<AudioFrame> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let id = UUID()
            subscribers[id] = continuation
            continuation.onTermination = { _ in Task { @MainActor in self.subscribers[id] = nil } }
        }
    }
    var level: AnyPublisher<Float, Never> { Just(0).eraseToAnyPublisher() }
    var deviceChanges: AnyPublisher<[AudioDevice], Never> { Just(devices).eraseToAnyPublisher() }
    func startMicrophone() async throws { holders += 1 }
    func stopMicrophone() { holders = max(0, holders - 1) }
    func startSystemAudio() async throws { isCapturingSystemAudio = true }
    func stopSystemAudio() { isCapturingSystemAudio = false }
    func muteOutput() { muted += 1 }
    func unmuteOutput() { muted -= 1 }
    func play(_ cue: SoundCue) { cues.append(cue) }

    /// Delivers samples as 40 ms frames on one channel; the other channel, when `both`, gets silence at the same times.
    func feed(_ samples: [Float], channel: AudioChannel = .mic, both: Bool = false) {
        var offset = 0
        while offset < samples.count {
            let end = min(samples.count, offset + 640)
            var block = Array(samples[offset..<end])
            if block.count < 640 { block += [Float](repeating: 0, count: 640 - block.count) }
            let time = clock
            clock += 0.04
            let frame = AudioFrame(channel: channel, samples: block, time: time, level: 0)
            for continuation in subscribers.values {
                continuation.yield(frame)
                if both { continuation.yield(AudioFrame(channel: channel == .mic ? .system : .mic, samples: [Float](repeating: 0, count: 640), time: time, level: 0)) }
            }
            offset = end
        }
    }
}

@MainActor private final class E2EInserter: TextInserting {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.udsy.superflow.selftest.\(UUID().uuidString)"))
    var selection: String?
    var inserted: [String] = []
    var replaced: [String] = []
    var editedVersion: String?
    var secure = false
    /// Set to make every insertion fail the way a paste into nothing does.
    var refuse: String?

    func insert(_ text: String, actions: [PostInsertAction], method: InsertionMethod) async -> InsertionOutcome {
        if secure { return .blockedSecureField }
        if let refuse { return .notInserted(reason: refuse) }
        inserted.append(text)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return .inserted
    }
    func selectedText() async -> String? { selection }
    func replaceSelection(with text: String) async -> InsertionOutcome {
        replaced.append(text)
        selection = text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return .inserted
    }
    func copyToClipboard(_ text: String) { pasteboard.clearContents(); pasteboard.setString(text, forType: .string) }
    func observeEdits(of insertedText: String, window: TimeInterval) async -> String? { editedVersion }
}

@MainActor private final class E2EContext: AppContextReading {
    var context = AppContext(app: AppRecord(bundleID: "com.apple.Notes", name: "Notes", category: .document), isEditable: true, fieldRole: "AXTextArea")
    func snapshot() -> AppContext { context }
    var frontmostApp: AppRecord? { context.app }
}

@MainActor private final class E2EFlowBar: FlowBarPresenting {
    var state: FlowBarState = .resting
    var states: [FlowBarState] = []
    var phases: [MeetingBarPhase?] = []
    var notifications: [FlowBarNotification] = []
    var liveTexts: [String] = []
    func setState(_ state: FlowBarState) { self.state = state; states.append(state) }
    func setMeetingPhase(_ phase: MeetingBarPhase?) { phases.append(phase) }
    func setLevel(_ level: Float) {}
    func setEdge(_ edge: FlowBarEdge) {}
    func setRestingVisible(_ visible: Bool) {}
    var actions: [String: (String) -> Void] = [:]
    func show(_ notification: FlowBarNotification, onAction: @escaping (String) -> Void) {
        notifications.append(notification)
        actions[notification.id] = onAction
    }
    var dismissed: [String] = []
    func dismiss(notificationID: String) { dismissed.append(notificationID) }
    func showMeetingPrompt(_ prompt: MeetingPrompt, onAnswer: @escaping (MeetingPromptAnswer) -> Void) {}
    func showLiveText(_ text: String?) { if let text { liveTexts.append(text) } }
    /// Clicks a card's button.
    func click(_ id: String, _ action: String) { actions[id]?(action) }
}

@MainActor private final class E2EHub: HubPresenting {
    var pages: [HubPage] = []
    var panes: [SettingsPane] = []
    func show(_ page: HubPage) { pages.append(page) }
    func showSettings(_ pane: SettingsPane) { panes.append(pane) }
    func showMeeting(_ id: UUID) {}
    func showNotepad(for meetingID: UUID) {}
    func showQuickNote() {}
    var isVisible: Bool { false }
}

/// A scripted speech engine for the fakes-only coordinator test: every clip stream yields one fixed transcript.
@MainActor private final class E2EScriptedSpeech: SpeechRecognizing {
    var text = "hello world"
    /// Set to make recognition fail (the engine crashed or isn't loaded).
    var error: Error?
    /// Samples the last one-shot transcription was given ("Retry transcript").
    var lastClipSamples = 0
    /// Set to make loading the engine fail (a damaged model file).
    var prepareError: Error?
    var availableEngines: [String] { ["scripted"] }
    var activeEngineID: String? = "scripted"
    func prepare(modelID: String) async throws {
        if let prepareError { throw prepareError }
        activeEngineID = modelID
    }
    func unload() {}
    func transcribe(_ audio: AudioClip, options: TranscriptionOptions, priority: SpeechPriority) async throws -> Transcript {
        if let error { throw error }
        lastClipSamples = audio.samples.count
        return Transcript(text: text)
    }
    func transcribeIncrementally(_ audio: AsyncStream<AudioClip>, options: TranscriptionOptions, priority: SpeechPriority)
        -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var heard = 0
                for await clip in audio { heard += clip.samples.filter { $0 != 0 }.count }
                if let error = self.error { continuation.finish(throwing: error); return }
                guard heard > 0 else { continuation.finish(throwing: SpeechError.noSpeech); return }
                continuation.yield(.partial(self.text))
                continuation.yield(.final(Transcript(text: self.text, segments: [TranscriptSegment(start: 0, end: 1, text: self.text)])))
                continuation.finish()
            }
        }
    }
    func speechSegments(in audio: AudioClip) async -> [Range<Int>] { [] }
    func diarize(_ audio: AudioClip) async throws -> [TranscriptSegment] { [] }
}

@MainActor private final class E2EModels: ModelManaging {
    var catalog: [ModelDescriptor] { ModelCatalog.all }
    var states: [String: ModelState] = [:]
    func state(of id: String) -> ModelState { states[id] ?? .installed }
    var locations: [String: URL] = [:]
    func location(of id: String) -> URL? { locations[id] }
    var downloads: [String] = []
    func download(_ id: String) -> AsyncThrowingStream<DownloadProgress, Error> {
        downloads.append(id)
        return AsyncThrowingStream { $0.finish() }
    }
    func pause(_ id: String) {}
    func delete(_ id: String) throws {}
    func importModel(_ id: String, from file: URL) async throws {}
    var diskUsage: Int64 { 0 }
    var changes: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
    func startAutomaticDownloads() {}
    var busy: [Bool] = []
    func setUserBusy(_ busy: Bool) { self.busy.append(busy) }
    var autoDownloadStatus: AutoDownloadStatus = .upToDate
    var readinesses: [String: Double] = [:]
    func readiness(of id: String) -> Double? { readinesses[id] }
}

/// A cleanup model that takes `loadSeconds` to load: the rules clean until it is loaded, then the text counts as the
/// model's; transforms upper-case the selection once loaded and throw `modelNotReady` before.
@MainActor private final class E2ELoadingCleaner: TextCleaning {
    private let rules = TextCleaner()
    var loadSeconds: TimeInterval = 0.8
    private(set) var loaded = false
    var prepares: [String] = []
    func isModelReady(for role: LanguageModelRole) -> Bool { role == .cleanup && loaded }
    func prepare(modelID: String, role: LanguageModelRole) async throws {
        prepares.append(modelID)
        try await Task.sleep(nanoseconds: UInt64(loadSeconds * 1_000_000_000))
        loaded = true
    }
    func unload(role: LanguageModelRole) { if role == .cleanup { loaded = false } }
    func warm(style: WritingStyle, level: CleanupLevel, category: AppCategory) async {}
    func clean(_ input: CleanupInput, budget: TimeInterval) async -> CleanupOutput {
        let output = await rules.clean(input, budget: budget)
        return loaded ? CleanupOutput(text: output.text, actions: output.actions) : output
    }
    func transform(_ text: String, instruction: String) async throws -> String {
        guard loaded else { throw TransformError.modelNotReady }
        return text.uppercased()
    }
    func generate(_ input: String, instruction: String, role: LanguageModelRole) async throws -> String { throw TransformError.modelNotReady }
}

/// Swaps every service the coordinator touches for one test and puts the previous ones back.
@MainActor private final class E2EServices {
    let hotkeys = E2EHotkeys(), audio = E2EAudio(), inserter = E2EInserter(), context = E2EContext(), flowBar = E2EFlowBar(), hub = E2EHub()
    let store: SQLiteStore
    let coordinator = DictationCoordinator()
    private let saved: (HistoryStoring?, MeetingStoring?, AudioCapturing?, SpeechRecognizing?, ModelManaging?, TextCleaning?, TextInserting?,
                        HotkeyMonitoring?, AppContextReading?, FlowBarPresenting?, HubPresenting?, MeetingRecording?, MeetingSummarizing?, DictationControlling?)

    init(speech: SpeechRecognizing, models: ModelManaging, cleanup: TextCleaning) {
        saved = (Services.history, Services.meetings, Services.audio, Services.speech, Services.models, Services.cleanup, Services.insertion,
                 Services.hotkeys, Services.context, Services.flowBar, Services.hub, Services.meetingRecorder, Services.summarizer, Services.dictation)
        store = SQLiteStore.open(at: SuperFlowPaths.support.appendingPathComponent("e2e-\(UUID().uuidString).sqlite"))
        Services.history = store
        Services.meetings = store
        Services.audio = audio
        Services.speech = speech
        Services.models = models
        Services.cleanup = cleanup
        Services.insertion = inserter
        Services.hotkeys = hotkeys
        Services.context = context
        Services.flowBar = flowBar
        Services.hub = hub
        Services.dictation = coordinator
    }

    func restore() {
        coordinator.deactivate()
        Services.history = saved.0; Services.meetings = saved.1; Services.audio = saved.2; Services.speech = saved.3; Services.models = saved.4
        Services.cleanup = saved.5; Services.insertion = saved.6; Services.hotkeys = saved.7; Services.context = saved.8; Services.flowBar = saved.9
        Services.hub = saved.10; Services.meetingRecorder = saved.11; Services.summarizer = saved.12; Services.dictation = saved.13
    }
}

/// Turns the run loop until the condition holds or the time is up.
@MainActor @discardableResult private func e2eWait(_ seconds: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}

private func e2eWords(_ text: String) -> String { text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ") }

// MARK: - Coordinator with fakes (always runs)

@MainActor private func endToEndCoordinatorFakes() {
    let speech = E2EScriptedSpeech()
    let services = E2EServices(speech: speech, models: E2EModels(), cleanup: TextCleaner())
    defer { services.restore() }
    let c = services.coordinator
    c.activate()
    var statuses: [DictationStatus] = []
    let subscription = c.statusChanges.sink { statuses.append($0) }
    defer { subscription.cancel() }

    // Push-to-talk: Fn down, speech, Fn up → rules-only cleanup (no model) → inserted → history.
    speech.text = "um send the invoice to priya tomorrow"
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "Fn down: listening (\(c.status))")
    check(services.audio.holders == 1 && services.audio.muted == 1 && services.audio.cues == [.dictationStart], "microphone held, output muted, start cue")
    services.audio.feed([Float](repeating: 0.1, count: 16_000))
    services.hotkeys.send(.released(.pushToTalk, fnChord))
    check(e2eWait { c.status == .idle }, "Fn up: back to idle (\(c.status))")
    check(statuses == [.idle, .initializing, .listening, .stopping, .processing, .idle], "status machine: \(statuses)")
    check(services.inserter.inserted == ["Send the invoice to priya tomorrow."], "rules cleaned and inserted: \(services.inserter.inserted)")
    check(services.inserter.pasteboard.string(forType: .string) == "Send the invoice to priya tomorrow.", "the text went to the private pasteboard")
    check(services.audio.holders == 0 && services.audio.muted == 0 && services.audio.cues.last == .dictationStop, "microphone released, output restored, stop cue")
    let row = services.store.lastDictation
    check(row?.rawText == speech.text && row?.cleanedText == "Send the invoice to priya tomorrow." && row?.outcome == .fallback && row?.mode == .pushToTalk,
          "history row: \(String(describing: row))")
    check(row?.audioFile != nil && FileManager.default.fileExists(atPath: SuperFlowPaths.dictationAudio.appendingPathComponent(row?.audioFile ?? "").path),
          "dictation audio kept for playback")
    check(services.flowBar.states.contains(.initializing) && services.flowBar.states.contains(.listening(mode: .pushToTalk))
              && services.flowBar.states.contains(.processing) && services.flowBar.state == .resting, "Flow Bar states: \(services.flowBar.states)")
    check(c.lastResult?.usedLLM == false && c.lastResult?.outcome == .inserted, "result reported")

    // Undo AI edit: the history row shows the raw transcript.
    if var undone = row {
        undone.usesRawText = true
        try? services.store.save(undone)
        check(services.store.dictation(undone.id)?.displayText == speech.text, "undo AI edit shows the raw transcript")
    }

    // Fn then Space (no release in between) turns the session hands-free; live text shows; Fn+Space again stops it,
    // and the duplicate hands-free press that follows does not start another session.
    speech.text = "quick note"
    services.flowBar.states = []
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "second session listening")
    services.hotkeys.send(.pressed(.handsFree, fnSpace))
    check(e2eWait { c.mode == .handsFree }, "Fn then Space: hands-free (\(String(describing: c.mode)))")
    check(services.flowBar.states.last == .listening(mode: .handsFree) && services.audio.cues.last == .handsFreeLock, "the bar and the lock cue follow")
    services.hotkeys.send(.released(.pushToTalk, fnChord))
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    check(c.status == .listening, "Fn up does not end a locked session")
    services.audio.feed([Float](repeating: 0.1, count: 8_000))
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    services.hotkeys.send(.pressed(.handsFree, fnSpace))
    check(e2eWait { c.status == .idle }, "stopped with Fn+Space")
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    check(c.status == .idle && services.inserter.inserted.count == 2, "the duplicate press started nothing (\(services.inserter.inserted.count) insertions)")
    check(services.flowBar.liveTexts.last == "quick note", "live text while hands-free: \(services.flowBar.liveTexts)")

    // Other-key cancel: a stray key inside the first second dismisses with a card and inserts nothing.
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "third session listening")
    services.hotkeys.send(.otherKey(during: .pushToTalk, fnChord))
    check(e2eWait { c.status == .dismissed }, "other key: dismissed (\(c.status))")
    check(services.flowBar.notifications.last?.id == "dictation.otherKey" && services.inserter.inserted.count == 2, "card shown, nothing inserted")
    check(services.audio.holders == 0, "microphone released on dismiss")

    // A secure field: nothing starts, a card explains.
    services.context.context.isSecure = true
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    check(c.status.canStart && services.flowBar.notifications.last?.id == "dictation.secureField", "password field refused with a card")
    services.context.context.isSecure = false
    services.hotkeys.send(.released(.pushToTalk, fnChord))

    // No speech: a tap that heard nothing is silent; a longer session shows "We couldn't hear you".
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "fourth session listening")
    services.audio.feed([Float](repeating: 0, count: 640))
    services.hotkeys.send(.released(.pushToTalk, fnChord))
    check(e2eWait { c.status == .idle }, "no-speech session ends")
    check(services.inserter.inserted.count == 2 && services.flowBar.notifications.last?.id != "dictation.noSpeech", "a short silent tap shows nothing")

    // Command Mode with the setting off: a card; on: Fn then Control rewrites the selection without a model (case change).
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "fifth session listening")
    services.hotkeys.send(.pressed(.commandMode, fnCtrl))
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    check(services.flowBar.notifications.last?.id == "dictation.commandModeOff" && c.mode == .pushToTalk, "Command Mode off: card, still push-to-talk")
    services.hotkeys.send(.released(.pushToTalk, fnChord))
    check(e2eWait { c.status == .idle }, "ended")
    Defaults[.commandModeEnabled] = true
    defer { Defaults.reset(.commandModeEnabled) }
    services.inserter.selection = "hello world"
    speech.text = "make this all caps"
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "sixth session listening")
    services.hotkeys.send(.pressed(.commandMode, fnCtrl))
    check(e2eWait { c.mode == .command }, "Fn then Control: Command Mode")
    services.audio.feed([Float](repeating: 0.1, count: 8_000))
    services.hotkeys.send(.released(.commandMode, fnCtrl))
    check(e2eWait { c.status == .idle }, "Command Mode finished (\(c.status))")
    check(services.inserter.replaced == ["HELLO WORLD"], "the selection was rewritten: \(services.inserter.replaced)")
    check(services.store.lastDictation?.mode == .command && services.store.lastDictation?.rawText == "make this all caps", "Command Mode row in history")
    check(services.flowBar.states.contains(.transformProcessing(label: "Command Mode")) && services.flowBar.states.contains(.transformCompleted), "Command Mode bar states")

    // On Rules only, a command or transform that needs the model gets a card that opens Settings › Models, never a
    // "getting ready" that cannot resolve; with a model chosen (still downloading or loading) "getting ready" stays.
    Defaults[.cleanupModelID] = nil
    defer { Defaults.reset(.cleanupModelID) }
    let noModel = { (card: FlowBarNotification?) in
        card?.id == "transform.noCleanupModel" && card?.title == "Command Mode needs a cleanup model"
            && card?.subtitle == "Choose one in Settings › Models." && card?.variant == .error && card?.actions == ["Open Settings"]
    }
    speech.text = "make this sound more formal"
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "seventh session listening")
    services.hotkeys.send(.pressed(.commandMode, fnCtrl))
    check(e2eWait { c.mode == .command }, "Command Mode on Rules only")
    services.audio.feed([Float](repeating: 0.1, count: 8_000))
    services.hotkeys.send(.released(.commandMode, fnCtrl))
    check(e2eWait { noModel(services.flowBar.notifications.last) }, "Rules only: Command Mode card (\(String(describing: services.flowBar.notifications.last)))")
    check(e2eWait { c.status.canStart } && services.inserter.replaced == ["HELLO WORLD"], "nothing replaced")
    services.flowBar.click("transform.noCleanupModel", "Open Settings")
    check(services.hub.panes == [.models], "Open Settings opens Settings › Models: \(services.hub.panes)")
    // Transforms: each run ends by resting the bar, after which the next one may start.
    let transform = { (expect: (FlowBarNotification?) -> Bool) -> Bool in
        let shown = services.flowBar.notifications.count
        services.flowBar.states.removeAll()
        services.hotkeys.send(.pressed(.transform, KeyChord(1)))
        let carded = e2eWait { services.flowBar.notifications.count > shown && expect(services.flowBar.notifications.last) }
        return carded && e2eWait { services.flowBar.states.last == .resting }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(DictationLimits.completedStateDuration + 0.2))
    check(transform(noModel), "Rules only: a transform gets the same card (\(String(describing: services.flowBar.notifications.last)))")
    services.flowBar.click("transform.noCleanupModel", "Open Settings")
    check(services.hub.panes == [.models, .models], "the transform card opens Settings › Models too")
    Defaults[.cleanupModelID] = ModelCatalog.qwen35_2B.id
    let gettingReady = { (card: FlowBarNotification?) in
        card?.id == "transform.failed" && card?.title == "Just a moment - Super Flow is getting ready..." && card?.variant == .alert
    }
    check(transform(gettingReady), "a chosen model still loading keeps getting ready (\(String(describing: services.flowBar.notifications.last)))")

    // A chosen model whose download failed: a card names why, "Try again" queues it again, "Open Settings" opens Models.
    // "Getting ready" stays only while it is actually downloading or queued.
    let qwen = ModelCatalog.qwen35_2B.id
    let models = Services.models as! E2EModels
    let couldNotLoad = { (reason: String) in { (card: FlowBarNotification?) in
        card?.id == "transform.cleanupModelFailed" && card?.title == "Couldn't load the cleanup model" && card?.subtitle == reason
            && card?.variant == .error && card?.actions == ["Try again", "Open Settings"]
    } }
    models.states[qwen] = .damaged
    check(transform(couldNotLoad("The download was damaged.")), "damaged download card (\(String(describing: services.flowBar.notifications.last)))")
    services.flowBar.click("transform.cleanupModelFailed", "Try again")
    check(models.downloads == [qwen], "Try again queues the download again: \(models.downloads)")
    services.flowBar.click("transform.cleanupModelFailed", "Open Settings")
    check(services.hub.panes == [.models, .models, .models], "the failure card opens Settings › Models")
    models.states[qwen] = .notDownloaded
    models.autoDownloadStatus = .waitingForDisk(freeBytes: 1_000)
    check(transform(couldNotLoad("Not enough disk space.")), "disk full card (\(String(describing: services.flowBar.notifications.last)))")
    models.autoDownloadStatus = .upToDate
    check(transform(couldNotLoad("Something went wrong loading it.")), "a download that stopped gets the generic card")
    models.readinesses[qwen] = 0.2
    check(transform(gettingReady), "queued for download keeps getting ready")
    models.readinesses[qwen] = nil
    models.states[qwen] = .downloading(fraction: 0.4)
    check(transform(gettingReady), "downloading keeps getting ready")
    models.states[qwen] = nil
    Defaults[.cleanupModelID] = nil

    // Esc with nothing running closes cards; paste-last re-inserts the last transcript.
    services.hotkeys.send(.released(.pasteLastText, KeyChord(1, 2)))
    check(e2eWait { services.inserter.inserted.count == 3 }, "paste last transcript")
    check(services.inserter.inserted.last == "HELLO WORLD", "pastes the last row's text")
    check(services.hub.pages.isEmpty, "nothing opened the hub")
}

// MARK: - Words survive failures (always runs)

/// Every way a dictation can fail after the user spoke keeps their words: the engine failing (audio kept, Retry
/// transcript), a cancel after speaking, a paste that lands nowhere (clipboard untouched, one click copies), a
/// microphone unplugged mid-sentence, and a cleanup model that won't load.
@MainActor private func endToEndWordsSurviveFailures() {
    let speech = E2EScriptedSpeech()
    let services = E2EServices(speech: speech, models: E2EModels(), cleanup: TextCleaner())
    defer { services.restore() }
    let c = services.coordinator
    c.activate()
    func dictate(_ seconds: Double, release: Bool = true) {
        services.hotkeys.send(.pressed(.pushToTalk, fnChord))
        check(e2eWait { c.status == .listening }, "listening (\(c.status))")
        services.audio.feed([Float](repeating: 0.1, count: Int(seconds * 16_000)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))   // the frames reach the recording
        if release { services.hotkeys.send(.released(.pushToTalk, fnChord)) }
    }
    func rawFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.dictationAudio.path)) ?? []).filter { !$0.hasSuffix(".caf") }
    }

    // The engine fails: no text, but the audio becomes a History row that "Retry transcript" turns into words.
    speech.error = SpeechError.failed("The speech engine stopped.")
    dictate(2)
    check(e2eWait { c.status == .error }, "an engine failure ends in error (\(c.status))")
    guard let failed = services.store.lastDictation else { check(false, "the failed dictation is kept"); return }
    check(failed.outcome == .error && failed.cleanedText.isEmpty && failed.audioFile != nil && abs(failed.duration - 2) < 0.1,
          "kept with its audio: \(failed.outcome) \(failed.duration) s")
    check(services.flowBar.notifications.last?.id == "dictation.failed" && services.flowBar.notifications.last?.actions == ["Open History"],
          "the card points to History")
    check(DictationActions.canRetry(failed) && DictationActions.notice(for: failed)?.contains("retry") == true, "History offers Retry transcript")
    check(rawFiles().isEmpty, "no raw recording is left behind")
    speech.error = nil
    speech.text = "send the quarterly numbers to priya"
    if case .failure(let error)? = complete(10, { try await c.retryTranscription(failed.id) }) { check(false, "retry failed: \(error)") }
    let retried = services.store.dictation(failed.id)
    check(retried?.cleanedText == "Send the quarterly numbers to priya." && retried?.outcome == .fallback && retried?.wordCount == 6,
          "Retry transcript fills the row: \(String(describing: retried?.cleanedText))")
    check(speech.lastClipSamples == 32_000 && c.status.canStart, "from the whole saved audio, beside the dictation state: \(speech.lastClipSamples)")

    // Retry waits for a dictation to finish; a quick cancel keeps nothing.
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "listening again")
    if case .failure(let error)? = complete(10, { try await c.retryTranscription(failed.id) }) {
        check(error as? DictationRetryError == .busy, "no retry while dictating")
    } else { check(false, "retry during a dictation must be refused") }
    let rows = services.store.dictations(matching: "", limit: 100, offset: 0).count
    services.hotkeys.send(.pressed(.dismiss, KeyChord(UInt16(kVK_Escape))))
    check(e2eWait { c.status == .dismissed } && services.store.dictations(matching: "", limit: 100, offset: 0).count == rows, "a tap cancelled keeps nothing")

    // Cancelled after speaking: kept as a cancelled row with its audio.
    dictate(2, release: false)
    services.hotkeys.send(.pressed(.dismiss, KeyChord(UInt16(kVK_Escape))))
    check(e2eWait { c.status == .dismissed }, "cancelled")
    let cancelled = services.store.lastDictation
    check(cancelled?.outcome == .dismissed && cancelled?.audioFile != nil && cancelled.map(DictationActions.canRetry) == true,
          "a cancelled dictation can be recovered")
    let gone = cancelled!
    try? FileManager.default.removeItem(at: SuperFlowPaths.dictationAudio.appendingPathComponent(gone.audioFile ?? ""))
    if case .failure(let error)? = complete(10, { try await c.retryTranscription(gone.id) }) {
        check(error as? DictationRetryError == .audioUnavailable, "audio gone: says so")
    } else { check(false, "retry without audio must fail") }

    // The paste lands nowhere: the words are in History, the user's clipboard is untouched, and one click copies them.
    services.inserter.refuse = "no_focused_element"
    services.inserter.pasteboard.clearContents()
    services.inserter.pasteboard.setString("the user's own clipboard", forType: .string)
    speech.text = "call the bank tomorrow"
    dictate(1)
    check(e2eWait { c.status == .idle }, "paste failure ends normally")
    check(services.store.lastDictation?.cleanedText == "Call the bank tomorrow." && services.store.lastDictation?.audioFile != nil,
          "the words and audio are in History")
    let card = services.flowBar.notifications.last
    check(card?.id == "dictation.clipboard" && card?.actions == ["Copy"] && card?.title.contains("V to paste") == true, "the card offers Copy and the paste-last shortcut: \(String(describing: card?.title))")
    check(services.inserter.pasteboard.string(forType: .string) == "the user's own clipboard", "the clipboard is left alone")
    services.flowBar.click("dictation.clipboard", "Copy")
    check(services.inserter.pasteboard.string(forType: .string) == "Call the bank tomorrow.", "one click copies the words")
    services.inserter.refuse = nil

    // The microphone is unplugged mid-sentence: the dictation finishes with what was heard instead of listening forever.
    speech.text = "the first half"
    RunLoop.main.run(until: Date().addingTimeInterval(DictationLimits.debounceWindow + 0.1))
    services.hotkeys.send(.pressed(.handsFree, fnSpace))
    check(e2eWait { c.status == .listening }, "hands-free listening")
    services.audio.feed([Float](repeating: 0.1, count: 16_000))
    check(e2eWait(8) { c.status == .idle }, "finished on its own when audio stopped (\(c.status))")
    check(services.inserter.inserted.last == "The first half." && services.flowBar.notifications.contains { $0.id == "dictation.micLost" },
          "what was said is inserted, and a card says why")
    check(services.audio.holders == 0, "microphone released")

    // A cleanup model that is installed but won't load: dictation goes on with the rules, and a card says so once.
    let broken = SuperFlowPaths.support.appendingPathComponent("broken-\(UUID().uuidString).gguf")
    try? Data("not a model".utf8).write(to: broken)
    let models = E2EModels()
    if let id = Defaults[.cleanupModelID] { models.locations[id] = broken }
    let brokenSpeech = E2EScriptedSpeech()
    brokenSpeech.activeEngineID = nil
    brokenSpeech.prepareError = SpeechError.failed("Couldn't load the speech model.")
    Defaults[.asrModelID] = "scripted"
    defer { Defaults.reset(.asrModelID) }
    let second = E2EServices(speech: brokenSpeech, models: models, cleanup: TextCleaner())
    defer { second.restore() }
    second.coordinator.activate()
    check(e2eWait(20) { second.flowBar.notifications.contains { $0.id == "dictation.cleanupModel" } }, "a card says the cleanup model didn't load")
    // A transform then says the model couldn't load instead of "getting ready"; "Try again" loads it again.
    second.inserter.selection = "fix this text"
    second.hotkeys.send(.pressed(.transform, KeyChord(1)))
    let loadFailed = { (card: FlowBarNotification?) in
        card?.id == "transform.cleanupModelFailed" && card?.subtitle == "Something went wrong loading it." && card?.actions == ["Try again", "Open Settings"]
    }
    check(e2eWait { loadFailed(second.flowBar.notifications.last) }, "load failure card (\(String(describing: second.flowBar.notifications.last)))")
    let shownBefore = second.flowBar.notifications.count
    second.flowBar.click("transform.cleanupModelFailed", "Try again")
    RunLoop.main.run(until: Date().addingTimeInterval(DictationLimits.completedStateDuration + 0.2))
    check(models.downloads.isEmpty && second.flowBar.notifications.count == shownBefore, "Try again reloads the installed model, no second load card")
    second.hotkeys.send(.pressed(.transform, KeyChord(1)))
    check(e2eWait { second.flowBar.notifications.count > shownBefore && loadFailed(second.flowBar.notifications.last) },
          "still unloadable: the card again")
    check(second.flowBar.notifications.contains { $0.id == "dictation.speechModel" && $0.variant == .error },
          "a card says the speech model didn't load and that nothing else can stand in")
}

/// Keep models in memory off: nothing loads at launch; the installed cleanup model loads at key-down (a dictation that
/// ends first uses the rules, the next one the model), and Command Mode and transforms show "getting ready" only while
/// it loads, then go on instead of waiting forever.
@MainActor private func endToEndCleanupModelOnDemand() {
    let qwen = ModelCatalog.qwen35_2B.id
    Defaults[.keepModelsInMemory] = false
    Defaults[.cleanupModelID] = qwen
    Defaults[.commandModeEnabled] = true
    defer { Defaults.reset(.keepModelsInMemory); Defaults.reset(.cleanupModelID); Defaults.reset(.commandModeEnabled) }
    let speech = E2EScriptedSpeech()
    let cleaner = E2ELoadingCleaner()
    let services = E2EServices(speech: speech, models: E2EModels(), cleanup: cleaner)
    defer { services.restore() }
    let c = services.coordinator
    c.activate()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    check(cleaner.prepares.isEmpty, "keep off: nothing loads at launch (\(cleaner.prepares))")

    // A dictation over before the model is ready: the rules alone, and the load carries on for the next one.
    speech.text = "please send the invoice to priya tomorrow"
    func dictate() {
        services.hotkeys.send(.pressed(.pushToTalk, fnChord))
        check(e2eWait { c.status == .listening }, "listening (\(c.status))")
        services.audio.feed([Float](repeating: 0.1, count: 3_200))
        services.hotkeys.send(.released(.pushToTalk, fnChord))
        check(e2eWait { c.status == .idle }, "dictation done (\(c.status))")
    }
    dictate()
    check(c.lastResult?.usedLLM == false && services.inserter.inserted.last == "Please send the invoice to priya tomorrow.",
          "still loading: rules only, no waiting (\(String(describing: c.lastResult?.usedLLM)))")
    check(cleaner.prepares == [qwen], "the load started at key-down: \(cleaner.prepares)")
    check(e2eWait(5) { cleaner.loaded }, "the load finished in the background")
    RunLoop.main.run(until: Date().addingTimeInterval(DictationLimits.debounceWindow + 0.1))
    dictate()
    check(c.lastResult?.usedLLM == true && cleaner.prepares == [qwen], "the next dictation uses the model, no second load")

    // A transform with the model let go (memory pressure): "getting ready" only while it loads, then the result.
    let loading = { (card: FlowBarNotification) in
        card.id == "transform.failed" && card.title == "Just a moment - Super Flow is getting ready..." && card.variant == .alert && card.timeout == nil
    }
    RunLoop.main.run(until: Date().addingTimeInterval(DictationLimits.completedStateDuration + 0.2))
    cleaner.unload(role: .cleanup)
    services.inserter.selection = "fix this text"
    let shown = services.flowBar.notifications.count
    services.hotkeys.send(.pressed(.transform, KeyChord(1)))
    check(e2eWait { services.flowBar.notifications.count > shown && loading(services.flowBar.notifications.last!) }, "getting ready while the model loads")
    check(services.inserter.replaced.isEmpty && services.flowBar.dismissed.isEmpty, "the transform waits for the load")
    check(e2eWait(5) { services.inserter.replaced == ["FIX THIS TEXT"] }, "then the transform goes on: \(services.inserter.replaced)")
    check(services.flowBar.dismissed == ["transform.failed"] && services.flowBar.notifications.count == shown + 1,
          "getting ready is dismissed after the load, and no other card (\(services.flowBar.dismissed))")
    check(cleaner.prepares == [qwen, qwen], "one load for the transform: \(cleaner.prepares)")

    // Command Mode: the load starts at key-down and the command waits on that same load, then rewrites the selection.
    check(e2eWait { services.flowBar.states.last == .resting }, "transform finished")
    cleaner.unload(role: .cleanup)
    services.inserter.selection = "hello world"
    speech.text = "make this all caps"
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "command session listening")
    services.hotkeys.send(.pressed(.commandMode, fnCtrl))
    check(e2eWait { c.mode == .command }, "Command Mode")
    services.audio.feed([Float](repeating: 0.1, count: 3_200))
    services.hotkeys.send(.released(.commandMode, fnCtrl))
    check(e2eWait(5) { c.status == .idle }, "Command Mode finished (\(c.status))")
    check(services.inserter.replaced.last == "HELLO WORLD", "the command ran on the loaded model: \(services.inserter.replaced)")
    check(cleaner.prepares == [qwen, qwen, qwen], "one load shared by key-down and the command: \(cleaner.prepares)")
    check(services.flowBar.dismissed == ["transform.failed", "transform.failed"], "getting ready dismissed again: \(services.flowBar.dismissed)")
}

/// History can't save (a full disk) or is turned off: the text still lands, paste-last still has it, and nothing is
/// written to disk when History is off.
@MainActor private func endToEndHistoryUnavailable() {
    let speech = E2EScriptedSpeech()
    let services = E2EServices(speech: speech, models: E2EModels(), cleanup: TextCleaner())
    defer { services.restore() }
    let full = E2EFullHistory(services.store)
    Services.history = full
    let c = services.coordinator
    c.activate()
    speech.text = "pick up the dry cleaning"
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "listening")
    services.audio.feed([Float](repeating: 0.1, count: 16_000))
    services.hotkeys.send(.released(.pushToTalk, fnChord))
    check(e2eWait { c.status == .idle }, "done")
    check(services.inserter.inserted.last == "Pick up the dry cleaning." && services.flowBar.notifications.last?.title == "Storage Full",
          "inserted, and a card says History couldn't save it")
    c.pasteLastTranscript()
    check(e2eWait { services.inserter.inserted.count == 2 } && services.inserter.inserted.last == "Pick up the dry cleaning.", "paste-last still has it")

    Services.history = services.store
    Defaults[.localDataPolicy] = .never
    defer { Defaults.reset(.localDataPolicy) }
    let filesBefore = (try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.dictationAudio.path)) ?? []
    speech.text = "private thought"
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "listening with History off")
    services.audio.feed([Float](repeating: 0.1, count: 16_000))
    check(((try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.dictationAudio.path)) ?? []) == filesBefore,
          "nothing is written to disk while History is off")
    services.hotkeys.send(.released(.pushToTalk, fnChord))
    check(e2eWait { c.status == .idle } && services.store.lastDictation == nil, "and nothing is saved")
    let insertions = services.inserter.inserted.count
    c.pasteLastTranscript()
    check(e2eWait { services.inserter.inserted.count == insertions + 1 } && services.inserter.inserted.last == "Private thought.",
          "paste-last works from memory")
}

/// A History whose dictation saves fail like a full disk; everything else goes to the real store.
@MainActor private final class E2EFullHistory: HistoryStoring {
    let store: SQLiteStore
    init(_ store: SQLiteStore) { self.store = store }
    func dictation(_ id: UUID) -> Dictation? { store.dictation(id) }
    func dictations(matching query: String, limit: Int, offset: Int) -> [Dictation] { store.dictations(matching: query, limit: limit, offset: offset) }
    var lastDictation: Dictation? { store.lastDictation }
    func save(_ dictation: Dictation) throws { throw StoreError.storageFull }
    func deleteDictation(_ id: UUID) throws { try store.deleteDictation(id) }
    func pruneDictations(before cutoff: Date) throws -> Int { try store.pruneDictations(before: cutoff) }
    func pruneDictationAudio(before cutoff: Date) throws -> Int { try store.pruneDictationAudio(before: cutoff) }
    func eraseDictations() throws -> Int { try store.eraseDictations() }
    func statistics(since: Date) -> (dictations: Int, words: Int, seconds: TimeInterval) { store.statistics(since: since) }
    var dictionary: [DictionaryEntry] { store.dictionary }
    func save(_ entry: DictionaryEntry) throws { try store.save(entry) }
    func deleteDictionaryEntry(_ id: UUID) throws { try store.deleteDictionaryEntry(id) }
    var snippets: [Snippet] { store.snippets }
    func save(_ snippet: Snippet) throws { try store.save(snippet) }
    func deleteSnippet(_ id: UUID) throws { try store.deleteSnippet(id) }
    var transforms: [TransformPrompt] { store.transforms }
    func save(_ transform: TransformPrompt) throws { try store.save(transform) }
    func deleteTransform(_ id: UUID) throws { try store.deleteTransform(id) }
    var notes: [ScratchNote] { store.notes }
    func save(_ note: ScratchNote) throws { try store.save(note) }
    func deleteNote(_ id: UUID) throws { try store.deleteNote(id) }
    var changes: AnyPublisher<StoreChange, Never> { store.changes }
}

/// The real thing: a child process dictates hands-free and is killed with SIGKILL mid-sentence. The next launch (this
/// process, on the child's folder) finds the audio, puts it in History, and "Retry transcript" gets the words back.
@MainActor private func endToEndKilledMidDictation() {
    let base = SuperFlowPaths.support.appendingPathComponent("killed-dictation-\(UUID().uuidString)", isDirectory: true)
    let line = CrashChild.runAndKill("dictation", base: base) { line in
        // While the child still dictates, this process is a second running copy: its recovery must leave the file be.
        let savedBase = SuperFlowPaths.base
        SuperFlowPaths.base = base
        defer { SuperFlowPaths.base = savedBase }
        let services = E2EServices(speech: E2EScriptedSpeech(), models: E2EModels(), cleanup: TextCleaner())
        defer { services.restore() }
        services.coordinator.activate()
        check(services.store.lastDictation == nil
                  && FileManager.default.fileExists(atPath: SuperFlowPaths.dictationAudio.appendingPathComponent("\(line).pcm").path),
              "a dictation another running copy is recording is left alone")
    }
    guard let line, let id = UUID(uuidString: line) else {
        check(false, "the child dictated and was killed"); return
    }
    let savedBase = SuperFlowPaths.base
    SuperFlowPaths.base = base
    defer { SuperFlowPaths.base = savedBase }
    let raw = SuperFlowPaths.dictationAudio.appendingPathComponent("\(id.uuidString).pcm")
    let size = (try? FileManager.default.attributesOfItem(atPath: raw.path)[.size] as? Int) ?? 0
    check(size >= 3 * 16_000 * 4, "the audio up to the kill is on disk (\(size) bytes)")

    let speech = E2EScriptedSpeech()
    let services = E2EServices(speech: speech, models: E2EModels(), cleanup: TextCleaner())
    defer { services.restore() }
    services.coordinator.activate()
    guard let row = services.store.dictation(id) else { check(false, "the interrupted dictation is in History"); return }
    check(row.outcome == .error && row.mode == .handsFree && row.app?.bundleID == "com.apple.Notes" && row.duration >= 3 && row.audioFile != nil,
          "with its audio, app and mode: \(row.outcome) \(row.duration) s")
    check(services.flowBar.notifications.last?.id == "dictation.recovered", "a card says it was recovered")
    check(!FileManager.default.fileExists(atPath: raw.path), "the raw recording became the kept audio")
    speech.text = "the words before the crash"
    if case .failure(let error)? = complete(10, { try await services.coordinator.retryTranscription(id) }) { check(false, "retry failed: \(error)") }
    check(services.store.dictation(id)?.cleanedText == "The words before the crash." && speech.lastClipSamples >= 3 * 16_000,
          "Retry transcript brings the words back: \(String(describing: services.store.dictation(id)?.cleanedText)) \(speech.lastClipSamples)")
}

/// The child process of `endToEndKilledMidDictation`: starts a hands-free dictation in Notes, says three seconds, prints
/// the dictation's id once the audio is on disk, and waits to be killed.
@MainActor func dictationCrashChild() -> Never {
    let services = E2EServices(speech: E2EScriptedSpeech(), models: E2EModels(), cleanup: TextCleaner())
    let c = services.coordinator
    c.activate()
    services.hotkeys.send(.pressed(.handsFree, fnSpace))
    guard e2eWait(10, { c.status == .listening }) else { exit(2) }
    services.audio.feed([Float](repeating: 0.1, count: 3 * 16_000))
    var raw: String?
    e2eWait(10) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.dictationAudio.path)) ?? []
        raw = names.first { name in
            name.hasSuffix(".pcm")
                && ((try? FileManager.default.attributesOfItem(atPath: SuperFlowPaths.dictationAudio.appendingPathComponent(name).path)[.size] as? Int) ?? 0)
                    >= 3 * 16_000 * 4
        }
        return raw != nil
    }
    guard let raw else { exit(3) }
    print(CrashChild.ready + String(raw.dropLast(4)))
    while true { RunLoop.main.run(until: Date().addingTimeInterval(1)) }
}

// MARK: - Dictation with the real engines (dev models)

@MainActor private func endToEndDictation() {
    guard Machine.isAppleSilicon, let manager = devManager(), manager.state(of: ModelCatalog.parakeetV3.id) == .installed,
          let (gguf, cleanupID) = devGGUF() else {
        print("  (skipped: needs Parakeet v3 and a GGUF in SUPERFLOW_DEV_MODELS)"); return
    }
    guard let dictated = spoken("Um, please send the quarterly report to Priya by Thursday afternoon.", voice: "Samantha"),
          let command = spoken("Make this all caps.", voice: "Samantha", padding: 0.4) else { print("  (skipped: no speech synthesiser)"); return }
    let engine = LlamaEngine(modelURL: gguf)
    let loadStarted = Date()
    guard case .success? = complete(300, { try await engine.load() }) else { check(false, "\(gguf.lastPathComponent) loads"); return }
    print("  cleanup model \(cleanupID) loaded in \(String(format: "%.1f", Date().timeIntervalSince(loadStarted))) s")
    let cleaner = TextCleaner(model: engine, modelID: cleanupID)
    let speech = SpeechService(models: manager)
    let services = E2EServices(speech: speech, models: manager, cleanup: cleaner)
    defer { services.restore(); speech.unload(); _ = complete { await engine.unload() } }
    Defaults[.cleanupModelID] = cleanupID
    Defaults[.selectedLanguages] = ["en"]
    defer { Defaults.reset(.cleanupModelID); Defaults.reset(.selectedLanguages) }
    let c = services.coordinator
    let warmStarted = Date()
    c.activate()
    check(e2eWait(600) { speech.activeEngineID == ModelCatalog.parakeetV3.id }, "the coordinator warms the speech engine at launch")
    print("  speech engine ready in \(String(format: "%.1f", Date().timeIntervalSince(warmStarted))) s")

    // Push-to-talk through the real pipeline.
    let started = Date()
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "listening")
    services.audio.feed(dictated)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let releasedAt = Date()
    services.hotkeys.send(.released(.pushToTalk, fnChord))
    check(e2eWait(180) { c.status == .idle }, "the dictation completes (\(c.status))")
    let total = Date().timeIntervalSince(releasedAt)
    guard let result = c.lastResult else { check(false, "a result"); return }
    let heard = e2eWords(result.insertedText)
    check(heard.contains("quarterly report") && heard.contains("priya") && heard.contains("thursday"), "recognised and inserted: '\(result.insertedText)'")
    check(!heard.hasPrefix("um"), "filler removed: '\(result.insertedText)'")
    check(services.inserter.pasteboard.string(forType: .string) == result.insertedText, "the private pasteboard holds the inserted text")
    let row = services.store.lastDictation
    check(row?.cleanedText == result.insertedText && row?.rawText == result.rawText && row?.app?.bundleID == "com.apple.Notes", "history row saved")
    check(row?.audioFile != nil, "audio kept")
    print("  dictation: key-up → inserted in \(String(format: "%.2f", total)) s (speech tail \(String(format: "%.2f", result.seconds.speech)) s, "
          + "cleanup \(String(format: "%.2f", result.seconds.cleanup)) s\(result.usedLLM ? " (LLM)" : " (rules only)"), insert \(String(format: "%.3f", result.seconds.insert)) s); "
          + "whole session \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
    print("  raw: \(result.rawText.debugDescription)\n  inserted: \(result.insertedText.debugDescription)")
    if var undone = row {
        undone.usesRawText = true
        try? services.store.save(undone)
        check(services.store.dictation(undone.id)?.displayText == result.rawText, "undo AI edit restores the raw transcript")
    }

    // Command Mode: spoken instruction over a selection.
    Defaults[.commandModeEnabled] = true
    defer { Defaults.reset(.commandModeEnabled) }
    services.inserter.selection = "hello there world"
    services.hotkeys.send(.pressed(.pushToTalk, fnChord))
    check(e2eWait { c.status == .listening }, "command session listening")
    services.hotkeys.send(.pressed(.commandMode, fnCtrl))
    check(e2eWait { c.mode == .command }, "Command Mode")
    services.audio.feed(command)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let commandReleased = Date()
    services.hotkeys.send(.released(.commandMode, fnCtrl))
    check(e2eWait(180) { c.status == .idle }, "Command Mode completes (\(c.status))")
    check(services.inserter.replaced.last == "HELLO THERE WORLD", "selection transformed: \(services.inserter.replaced)")
    print("  command mode: '\(c.lastResult?.rawText ?? "")' → \(services.inserter.replaced.last?.debugDescription ?? "-") in \(String(format: "%.2f", Date().timeIntervalSince(commandReleased))) s")
}

// MARK: - Meeting with the real engines (dev models)

@MainActor private func endToEndMeeting() {
    guard Machine.isAppleSilicon, let manager = devManager(), manager.state(of: ModelCatalog.parakeetV3.id) == .installed,
          manager.state(of: ModelCatalog.qwen35_4B.id) == .installed, let gguf = manager.location(of: ModelCatalog.qwen35_4B.id) else {
        print("  (skipped: needs Parakeet v3 and \(ModelCatalog.qwen35_4B.fileName) in SUPERFLOW_DEV_MODELS)"); return
    }
    let lines: [(AudioChannel, String, String)] = [
        (.mic, "Samantha", "Thanks for joining. Let's go through the launch plan and ship the beta on Friday."),
        (.system, "Daniel", "Sounds good. I will send the pricing proposal by Friday and update the support FAQ before launch."),
        (.mic, "Samantha", "Great. One open question is whether we offer a free tier at launch. Let's decide that next week."),
        (.system, "Daniel", "Agreed. I'll own the onboarding metrics review and share it next Tuesday."),
    ]
    var tracks: [(AudioChannel, [Float])] = []
    for (channel, voice, text) in lines {
        guard let audio = spoken(text, voice: voice, padding: 0.6) else { print("  (skipped: no speech synthesiser)"); return }
        tracks.append((channel, audio))
    }
    let engine = LlamaEngine(modelURL: gguf)
    guard case .success? = complete(300, { try await engine.load() }) else { check(false, "notes model loads"); return }
    let cleaner = TextCleaner(model: engine, modelID: ModelCatalog.qwen35_4B.id)
    let speech = SpeechService(models: manager)
    let services = E2EServices(speech: speech, models: manager, cleanup: cleaner)
    defer { services.restore(); speech.unload(); _ = complete { await engine.unload() } }
    Defaults[.notesModelID] = ModelCatalog.qwen35_4B.id
    Defaults[.cleanupModelID] = ModelCatalog.qwen35_4B.id
    Defaults[.notetakerAttributeNamesEnabled] = false   // no diarization set in the dev folders: speakers are You / Them
    Defaults[.notetakerOpenWindowOnRecord] = false
    defer { Defaults.reset(.notesModelID); Defaults.reset(.cleanupModelID); Defaults.reset(.notetakerAttributeNamesEnabled); Defaults.reset(.notetakerOpenWindowOnRecord) }
    let recorder = MeetingRecorder()
    recorder.persistInterval = 0.05
    Services.meetingRecorder = recorder
    Services.summarizer = MeetingSummarizer.shared

    let started = Date()
    guard case .success(let meeting)? = complete(60, { try await recorder.start(nil) }) else { check(false, "the meeting starts"); return }
    check(services.audio.holders == 1 && services.audio.isCapturingSystemAudio, "both captures held")
    check(e2eWait(600) { speech.activeEngineID != nil && cleaner.isModelReady(for: .notes) }, "speech and notes engines prepared for the meeting")
    for (channel, audio) in tracks { services.audio.feed(audio, channel: channel, both: true) }
    check(e2eWait(120) { (Services.meetings.meeting(meeting.id)?.segments.count ?? 0) >= 4 }, "live transcript has every utterance "
          + "(\(Services.meetings.meeting(meeting.id)?.segments.count ?? 0))")
    recorder.addMarker("Pricing")
    _ = complete(60) { await recorder.stop() }
    check(services.flowBar.phases.last == .some(nil) && services.flowBar.phases.contains { if case .recording? = $0 { return true }; return false },
          "meeting phases on the bar: \(services.flowBar.phases)")
    let processingStarted = Date()
    _ = complete(900) { await recorder.waitForProcessing() }
    guard let done = Services.meetings.meeting(meeting.id) else { check(false, "the meeting is stored"); return }
    let byChannel = Dictionary(grouping: done.segments, by: \.channel).mapValues { $0.map(\.text).joined(separator: " ") }
    check(e2eWords(byChannel[.mic] ?? "").contains("launch plan") && e2eWords(byChannel[.system] ?? "").contains("pricing proposal"),
          "each track transcribed on its own channel: \(byChannel)")
    check(Set(done.segments.map { done.speakerLabel(for: $0) }) == ["You", "Them"], "speakers by channel: \(Set(done.segments.map { done.speakerLabel(for: $0) }))")
    check(done.markers.map(\.label) == ["Pricing"], "marker kept")
    check(done.tracks.map(\.channel).sorted { $0.rawValue < $1.rawValue } == [.mic, .system], "two audio tracks written")
    guard let summary = done.summary else { check(false, "notes generated by the notes model"); return }
    check(!summary.summary.isEmpty && summary.modelID == ModelCatalog.qwen35_4B.id, "summary written by \(summary.modelID): \(summary.summary.debugDescription)")
    check(!summary.actionItems.isEmpty || !summary.decisions.isEmpty, "decisions or action items found: \(summary.decisions) \(summary.actionItems.map(\.text))")
    let markdown = MeetingExport.text(done, format: .markdown)
    check(markdown.contains("## Summary") && markdown.contains("**You**") && markdown.contains("**Them**") && markdown.contains("## Markers")
              && markdown.contains("Pricing"), "Markdown export has the summary, both speakers and the marker")
    let file = SuperFlowPaths.support.appendingPathComponent(MeetingExport.fileName(for: done, format: .markdown))
    check((try? MeetingExport.write(done, format: .markdown, to: file)) != nil && (try? String(contentsOf: file, encoding: .utf8)) == markdown, "export file written")
    print("  meeting: transcript in \(String(format: "%.1f", processingStarted.timeIntervalSince(started))) s, notes in "
          + "\(String(format: "%.1f", Date().timeIntervalSince(processingStarted))) s — title: \(summary.title)")
    print("  summary: \(summary.summary.replacingOccurrences(of: "\n", with: " / "))")
    print("  actions: \(summary.actionItems.map { "\($0.text) [\($0.owner ?? "-")]" })")
}

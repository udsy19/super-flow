import AppKit
import Combine
import Foundation
import SuperFlowCore

/// Registers the coordinator in `Services` (called once at launch, after every other module).
public enum DictationKitModule {
    @MainActor public static func install() {
        Services.dictation = DictationCoordinator.shared
    }
}

/// The dictation state machine (behaviour.md §2.2) and the pipeline behind it: hotkeys → Flow Bar states → microphone
/// (pre-roll and post-roll) → streaming recognition (live text while hands-free) → cleanup (rules and the local LLM
/// within budget, per-app style) → insertion at the cursor (never into a password field) → History → sounds. Also
/// Command Mode (Fn+Control over a selection), Transforms (⌥1–⌥3), the Notetaker shortcut, "Getting ready… N%" while
/// models download, and every failure as a plain card above the bar. Modules are reached only through `Services`.
@MainActor
public final class DictationCoordinator: DictationControlling {
    public static let shared = DictationCoordinator()

    private let statusSubject = CurrentValueSubject<DictationStatus, Never>(.idle)
    public private(set) var mode: DictationMode?
    public var status: DictationStatus { statusSubject.value }
    public var statusChanges: AnyPublisher<DictationStatus, Never> { statusSubject.eraseToAnyPublisher() }

    /// The clock; the self-test pins it.
    public var now: () -> Date = Date.init
    /// The last finished dictation's result, for the self-test and the hub.
    public private(set) var lastResult: Result?

    public struct Result: Equatable, Sendable {
        public var dictationID: UUID
        public var rawText: String
        public var insertedText: String
        public var usedLLM: Bool
        public var outcome: InsertionOutcome
        public var seconds: (speech: TimeInterval, cleanup: TimeInterval, insert: TimeInterval)
        public static func == (a: Result, b: Result) -> Bool { a.dictationID == b.dictationID }
    }

    private var session: Session?
    private var lastFinishAt: Date?
    private var hotkeyTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var transform: (name: String, task: Task<Void, Never>)?
    private var completedRevert: Task<Void, Never>?
    private var engineWarmup: Task<Void, Never>?
    /// The last text when it isn't in History (History is off, or saving failed): paste-last and copy-last use it.
    private var lastUnsavedText: String?
    private var reportedCleanupLoadFailure = false

    public init() {}

    // MARK: Launch

    /// Starts listening to the hotkeys, warms the engines that are installed, follows model installs, and points out a
    /// Globe-key setting that collides with Apple's dictation. Called once after every module is installed.
    public func activate() {
        guard hotkeyTask == nil else { return }
        recoverInterruptedDictations()
        let events = Services.hotkeys.events
        hotkeyTask = Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        Services.models.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in self?.modelChanged(id) }
            .store(in: &subscriptions)
        Defaults.changes
            .filter { [Defaults.Keys.asrModelID.name, Defaults.Keys.cleanupModelID.name, Defaults.Keys.keepModelsInMemory.name].contains($0) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.warmEngines() }
            .store(in: &subscriptions)
        warmEngines()
        if GlobeKey.collidesWithAppleDictation(Defaults[.shortcuts]), !Defaults[.shownPrompts].contains("globeKey") {
            Defaults[.shownPrompts].insert("globeKey")
            Services.flowBar.show(DictationNotices.globeKey()) { _ in
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
        }
    }

    /// Stops listening and lets go of every subscription (the self-test swaps services; the app never calls this).
    public func deactivate() {
        hotkeyTask?.cancel()
        hotkeyTask = nil
        engineWarmup?.cancel()
        engineWarmup = nil
        completedRevert?.cancel()
        subscriptions.removeAll()
        if session != nil { dismiss(.onboardingExited) }
    }

    /// Loads the dictation engine and the cleanup model as soon as they are installed (local-models.md §4: models
    /// resident, warmed after load) when the Mac keeps models in memory; otherwise the first key-down loads them.
    private func warmEngines() {
        guard Defaults[.keepModelsInMemory] else { return }
        engineWarmup?.cancel()
        engineWarmup = Task { @MainActor in
            let asr = Defaults[.asrModelID]
            if Services.models.state(of: asr) == .installed, Services.speech.activeEngineID != asr, Services.speech.availableEngines.contains(asr) {
                do { try await Services.speech.prepare(modelID: asr) } catch {
                    Log.app.error("Speech engine not ready: \(error.localizedDescription, privacy: .public)")
                }
            } else if Services.speech.activeEngineID == nil, let any = Services.speech.availableEngines.first {
                try? await Services.speech.prepare(modelID: any)
            }
            guard !Task.isCancelled, let cleanup = Defaults[.cleanupModelID] else { return }
            if Services.models.state(of: cleanup) == .installed, !Services.cleanup.isModelReady(for: .cleanup) {
                do { try await Services.cleanup.prepare(modelID: cleanup, role: .cleanup) } catch {
                    Log.app.error("Cleanup model not ready: \(error.localizedDescription, privacy: .public)")
                    // Installed but it won't load (a damaged file, too little memory): dictation keeps working on the
                    // rules alone; say so once rather than quietly writing rougher text.
                    let missing: Bool = { if case .modelNotInstalled? = error as? SpeechError { return true } else { return false } }()
                    if !missing, !self.reportedCleanupLoadFailure {
                        self.reportedCleanupLoadFailure = true
                        Services.flowBar.show(DictationNotices.cleanupModelFailed()) { _ in Services.hub.showSettings(.models) }
                    }
                }
            }
        }
    }

    private func modelChanged(_ id: String) {
        if let session, session.preparing, id == Defaults[.asrModelID] {
            if let fraction = Services.models.readiness(of: id) { Services.flowBar.setState(.preparing(fraction: fraction)) }
            else if Services.models.state(of: id) == .installed { Task { await self.beginCapture(session) } }
            return
        }
        guard Services.models.state(of: id) == .installed, [Defaults[.asrModelID], Defaults[.cleanupModelID]].contains(id) else { return }
        warmEngines()
    }

    // MARK: Hotkeys

    private var routerState: HotkeyRouter.State {
        HotkeyRouter.State(status: status, mode: mode, startedAt: session?.startedAt, lastFinishAt: lastFinishAt,
                           commandModeEnabled: Defaults[.commandModeEnabled], tripleTapEnabled: Defaults[.notetakerTripleTapShortcutEnabled],
                           transformsEnabled: Defaults[.polishEnabled])
    }

    /// Routes one hotkey event (also driven by the self-test).
    public func handle(_ event: HotkeyEvent) {
        let intent = HotkeyRouter.route(event, state: routerState, now: now())
        if intent != .none { Log.hotkeys.debug("\(String(describing: event), privacy: .public) → \(String(describing: intent), privacy: .public)") }
        switch intent {
        case .start(let mode): start(mode: mode, source: .keyboard)
        case .finish: finish()
        case .dismiss(let reason): dismiss(reason)
        case .switchMode(let mode): switchMode(to: mode)
        case .closeCards: closeCards()
        case .commandModeOff:
            Services.flowBar.show(DictationNotices.commandModeOff()) { _ in Defaults[.commandModeEnabled] = true }
        case .transform(let action): runTransform(action)
        case .notetaker: toggleNotetaker()
        case .pasteLast: pasteLastTranscript()
        case .copyLast: copyLastTranscript()
        case .openScratchpad: Services.hub.show(.scratchpad)
        case .secureInput(let blocked, let owner):
            if blocked {
                if status.isRecording { dismiss(.otherShortcut) }
                let name = owner.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName }
                Services.flowBar.show(DictationNotices.secureInput(owner: name)) { _ in }
            } else {
                Services.flowBar.dismiss(notificationID: DictationNotices.secureInput(owner: nil).id)
            }
        case .none: break
        }
    }

    private func closeCards() {
        for id in ["dictation.secureField", "dictation.noAudio", "dictation.noSpeech", "dictation.otherKey", "dictation.clipboard",
                   "transform.noSelection", "transform.failed", "dictation.failed", "dictation.learned", "dictation.preparing",
                   "dictation.micLost", "dictation.notSaved", "dictation.recovered", "dictation.cleanupModel"] {
            Services.flowBar.dismiss(notificationID: id)
        }
    }

    // MARK: DictationControlling

    public func start(mode: DictationMode, source: DictationSource) {
        guard status.canStart else { return }
        if let transform {
            Services.flowBar.show(DictationNotices.dictationDuringTransform(transform.name)) { _ in }
            return
        }
        let context = Services.context.snapshot()
        if context.isSecure {
            Services.flowBar.show(DictationNotices.secureField()) { _ in }
            Services.audio.play(.notificationError)
            return
        }
        let session = Session(mode: mode, source: source, context: context, startedAt: now())
        self.session = session
        self.mode = mode
        lastResult = nil
        completedRevert?.cancel()
        statusSubject.send(.initializing)
        Services.models.setUserBusy(true)
        Log.app.info("Dictation started: \(mode.rawValue, privacy: .public) from \(source.rawValue, privacy: .public)")
        if mode == .command, !Defaults[.shownPrompts].contains("commandMode") {
            Defaults[.shownPrompts].insert("commandMode")
            Services.flowBar.show(DictationNotices.firstCommandMode()) { _ in }
        }
        let asr = Defaults[.asrModelID]
        if Services.speech.availableEngines.isEmpty {
            if let fraction = Services.models.readiness(of: asr) {
                // Used before the model arrived: "Getting ready… N%" instead of an error; capture starts when it installs.
                session.preparing = true
                Services.flowBar.setState(.preparing(fraction: fraction))
                return
            }
            if Services.models.state(of: asr) != .installed {
                fail(session, with: DictationNotices.noSpeechModel())
                return
            }
        }
        Services.flowBar.setState(.initializing)
        Task { await beginCapture(session) }
    }

    public func finish() {
        guard status.isRecording, let session, self.session === session else { return }
        lastFinishAt = now()
        if session.preparing {
            Services.flowBar.show(DictationNotices.gettingReady(fraction: Services.models.readiness(of: Defaults[.asrModelID]))) { _ in }
            end(session, status: .dismissed)
            return
        }
        guard session.listening else {
            // Released before the microphone came up: nothing was heard.
            session.cancelled = true
            end(session, status: .dismissed)
            return
        }
        statusSubject.send(.stopping)
        Services.flowBar.setState(.processing)
        session.finishing = Task { await self.complete(session) }
    }

    public func dismiss(_ reason: DismissReason) {
        guard !status.canStart, let session, self.session === session else { return }
        Log.app.info("Dictation dismissed: \(reason.rawValue, privacy: .public)")
        session.cancelled = true
        session.finishing?.cancel()
        releaseCapture(session)
        // A cancelled dictation that heard something stays in History with its audio ("Retry transcript").
        keepForRetry(session, outcome: .dismissed)
        if reason == .otherShortcut, session.listening {
            Services.flowBar.show(DictationNotices.otherKey(shortcut: Defaults[.shortcuts].chords(for: .pushToTalk).first?.displayString ?? "Fn")) { _ in }
        }
        end(session, status: .dismissed)
    }

    public func pasteLastTranscript() {
        guard let text = lastText else { return }
        Task {
            if await Services.insertion.insert(text, actions: [], method: Defaults[.insertionMethod]) == .inserted {
                Services.audio.play(.paste)
            }
        }
    }

    public func copyLastTranscript() {
        guard let text = lastText else { return }
        Services.insertion.copyToClipboard(text)
        Services.flowBar.show(DictationNotices.transformCopied()) { _ in }
    }

    /// The last dictation's text: from History, or held here when it couldn't be saved there.
    private var lastText: String? { lastUnsavedText ?? Services.history.lastDictation?.displayText }

    // MARK: Capture

    /// Opens the microphone and starts the streaming recognition for a session that is ready to listen.
    private func beginCapture(_ session: Session) async {
        guard self.session === session, !session.cancelled else { return }
        session.preparing = false
        if session.mode == .command { session.selection = await Services.insertion.selectedText() ?? "" }
        guard self.session === session, !session.cancelled else { return }
        let frames = Services.audio.frames   // subscribed before the start, so the pre-roll history arrives first
        do {
            try await Services.audio.startMicrophone()
            session.holdsMicrophone = true
        } catch {
            fail(session, with: microphoneNotice(for: error))
            return
        }
        guard self.session === session, !session.cancelled else { releaseCapture(session); return }
        session.listening = true
        session.listeningSince = now()
        statusSubject.send(.listening)
        Services.flowBar.setState(.listening(mode: session.mode))
        Services.audio.muteOutput()
        Services.audio.play(session.mode == .handsFree ? .handsFreeLock : .dictationStart)

        if session.mode != .command {
            let style = styleProfile(for: session.context)
            Task { await Services.cleanup.warm(style: style.style, level: style.level, category: session.context.app?.category ?? .other) }
        }
        if Defaults[.localDataPolicy] != .never {
            session.recording = DictationRecording(DictationRecording.Info(id: session.id, startedAt: session.startedAt, app: session.context.app,
                                                                           mode: session.mode, source: session.source))
        }
        let (clips, clipContinuation) = AsyncStream<AudioClip>.makeStream()
        session.clips = clipContinuation
        let options = transcriptionOptions(for: session.context)
        let events = Services.speech.transcribeIncrementally(clips, options: options, priority: .dictation)
        session.transcription = Task { @MainActor [weak self] in
            do {
                for try await event in events {
                    switch event {
                    case .partial(let text):
                        session.partial = text
                        if session.mode == .handsFree { self?.showLiveText(text, for: session) }
                    case .segment: break
                    case .final(let transcript): return transcript
                    }
                }
            } catch SpeechError.noSpeech {
                return nil
            } catch {
                session.speechError = error
            }
            return nil
        }
        session.frames = Task { @MainActor in
            for await frame in frames where frame.channel == .mic {
                guard !session.cancelled, !session.stopped else { return }
                session.lastFrameAt = Date()
                session.recording?.append(frame.samples)
                clipContinuation.yield(AudioClip(samples: frame.samples, startTime: frame.time))
            }
        }
        session.watchdog = Task { @MainActor [weak self] in
            let started = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self, self.session === session, session.listening, !session.stopped else { return }
                if let last = session.lastFrameAt {
                    // Audio stopped arriving mid-dictation (the microphone was unplugged, or its permission withdrawn):
                    // finish with what was heard instead of listening to nothing.
                    guard Date().timeIntervalSince(last) >= DictationLimits.noAudioTimeout else { continue }
                    Services.flowBar.show(DictationNotices.microphoneLost()) { _ in }
                    self.finish()
                } else {
                    guard Date().timeIntervalSince(started) >= DictationLimits.noAudioTimeout else { continue }
                    Services.flowBar.show(DictationNotices.noAudio()) { _ in }
                    Services.audio.play(.notificationError)
                    self.dismiss(.noAudioDuringDictation)
                }
                return
            }
        }
        session.limit = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DictationLimits.sessionWarningAt * 1_000_000_000))
            guard !Task.isCancelled, let self, self.session === session, session.listening else { return }
            Services.flowBar.show(DictationNotices.almostTooLong()) { _ in }
            try? await Task.sleep(nanoseconds: UInt64((DictationLimits.maxSessionDuration - DictationLimits.sessionWarningAt) * 1_000_000_000))
            guard !Task.isCancelled, self.session === session, session.listening else { return }
            Services.flowBar.show(DictationNotices.tooLong()) { _ in }
            self.finish()
        }
    }

    private func showLiveText(_ text: String, for session: Session) {
        guard self.session === session, session.listening else { return }
        Services.flowBar.showLiveText(text.isEmpty ? nil : text)
    }

    /// Fn then Space (push-to-talk → hands-free) and Fn then Control (push-to-talk → Command Mode) while recording.
    private func switchMode(to mode: DictationMode) {
        guard let session, status.isRecording, session.mode != mode else { return }
        session.mode = mode
        self.mode = mode
        if mode == .command {
            Task { session.selection = await Services.insertion.selectedText() ?? "" }
            if !Defaults[.shownPrompts].contains("commandMode") {
                Defaults[.shownPrompts].insert("commandMode")
                Services.flowBar.show(DictationNotices.firstCommandMode()) { _ in }
            }
        }
        if session.listening {
            Services.flowBar.setState(.listening(mode: mode))
            if mode == .handsFree { Services.audio.play(.handsFreeLock) }
        }
    }

    private func releaseCapture(_ session: Session) {
        guard !session.stopped else { return }
        session.stopped = true
        session.watchdog?.cancel()
        session.limit?.cancel()
        session.frames?.cancel()
        session.clips?.finish()
        if session.holdsMicrophone {
            Services.audio.stopMicrophone()
            session.holdsMicrophone = false
        }
        if session.listening {
            Services.audio.unmuteOutput()
            Services.flowBar.showLiveText(nil)
        }
    }

    // MARK: Finish

    private func complete(_ session: Session) async {
        // Post-roll: the tail of the last word arrives after the key came up (local-models.md §2.8).
        try? await Task.sleep(nanoseconds: UInt64(DictationLimits.postRoll * 1_000_000_000))
        guard self.session === session, !session.cancelled else { return }
        let duration = now().timeIntervalSince(session.listeningSince ?? session.startedAt)
        releaseCapture(session)
        Services.audio.play(.dictationStop)
        statusSubject.send(.processing)
        let speechStarted = Date()
        let transcript = await session.transcription?.value
        let speechSeconds = Date().timeIntervalSince(speechStarted)
        guard self.session === session, !session.cancelled else { return }
        if let error = session.speechError {
            // The words aren't lost: the audio goes to History for "Retry transcript".
            let kept = keepForRetry(session, outcome: .error)
            fail(session, with: speechNotice(for: error, kept: kept))
            return
        }
        guard let transcript, !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if duration >= DictationLimits.silentTapDuration { Services.flowBar.show(DictationNotices.noSpeech()) { _ in } }
            end(session, status: .idle)
            return
        }
        session.heard = transcript
        switch session.mode {
        case .command: await runCommand(session, instruction: transcript.text, duration: duration)
        case .pushToTalk, .handsFree: await insert(session, transcript: transcript, duration: duration, speechSeconds: speechSeconds)
        }
    }

    private func insert(_ session: Session, transcript: Transcript, duration: TimeInterval, speechSeconds: TimeInterval) async {
        let context = session.context
        let style = styleProfile(for: context)
        let format = context.app.flatMap { Defaults[.appTranscriptionFormats][$0.bundleID] } ?? Defaults[.defaultTranscriptionFormat]
        let input = CleanupInput(transcript: transcript, context: context, style: style.style, level: style.level, format: format,
                                 dictionary: Services.history.dictionary, snippets: Services.history.snippets,
                                 detectStyle: Defaults[.styleDetectionEnabled])
        let cleanupStarted = Date()
        let output = await Services.cleanup.clean(input, budget: DictationLimits.cleanupBudget(words: Dictation.countWords(transcript.text)))
        let cleanupSeconds = Date().timeIntervalSince(cleanupStarted)
        guard self.session === session, !session.cancelled else { return }
        var text = output.text
        if text.isEmpty { text = transcript.text }
        let insertStarted = Date()
        let outcome = await Services.insertion.insert(text, actions: output.actions, method: Defaults[.insertionMethod])
        let insertSeconds = Date().timeIntervalSince(insertStarted)
        guard self.session === session else { return }

        var dictation = Dictation(id: session.id, createdAt: session.startedAt, rawText: transcript.text, cleanedText: text, app: context.app,
                                  language: transcript.language, duration: duration, mode: session.mode, source: session.source,
                                  outcome: output.usedLLM ? .formatted : output.skipReason == .clientDisabled ? .rawTranscript : .fallback)
        if outcome == .blockedSecureField { dictation.outcome = .error }
        // Audio is kept for playback and retry when History keeps everything, and for a text that didn't land anywhere.
        dictation.audioFile = settleAudio(session, keep: Defaults[.localDataPolicy] == .store || outcome != .inserted)
        remember(dictation)
        for id in output.expandedSnippets {
            guard var snippet = Services.history.snippets.first(where: { $0.id == id }) else { continue }
            snippet.useCount += 1
            try? Services.history.save(snippet)
        }
        lastResult = Result(dictationID: dictation.id, rawText: transcript.text, insertedText: text, usedLLM: output.usedLLM, outcome: outcome,
                            seconds: (speechSeconds, cleanupSeconds, insertSeconds))
        Log.app.info("Dictation \(dictation.outcome.rawValue, privacy: .public): speech \(Int(speechSeconds * 1000)) ms, cleanup \(Int(cleanupSeconds * 1000)) ms, insert \(Int(insertSeconds * 1000)) ms")

        switch outcome {
        case .inserted:
            if output.usedLLM, output.text != transcript.text { showCompleted(.cleanupCompleted, session) } else { end(session, status: .idle) }
            if Defaults[.shouldAutoLearnWords], !text.isEmpty { watchEdits(of: dictation) }
        case .notInserted(let reason) where reason == "accessibility_not_trusted":
            Services.flowBar.show(DictationNotices.accessibilityRequired()) { _ in Permissions.open(.accessibility) }
            end(session, status: .idle)
        case .notInserted:
            // The paste didn't land and the user's clipboard is back as it was: the words are in History and one click
            // (or the paste-last shortcut) away.
            Services.flowBar.show(DictationNotices.pasteFailed(shortcut: pasteLastShortcut)) { _ in
                Services.insertion.copyToClipboard(text)
                Services.flowBar.show(DictationNotices.transformCopied()) { _ in }
            }
            end(session, status: .idle)
        case .blockedSecureField:
            Services.flowBar.show(DictationNotices.blockedSecureInsert()) { _ in Services.hub.show(.history) }
            Services.audio.play(.notificationError)
            end(session, status: .idle)
        }
    }

    /// Command Mode (behaviour.md §10, Fn+Control): the spoken instruction rewrites the selection, or writes text when
    /// nothing was selected.
    private func runCommand(_ session: Session, instruction: String, duration: TimeInterval) async {
        Services.flowBar.setState(.transformProcessing(label: "Command Mode"))
        let selection = session.selection ?? ""
        do {
            let result = try await Services.cleanup.transform(selection, instruction: instruction)
            guard self.session === session, !session.cancelled else { return }
            let outcome = selection.isEmpty
                ? await Services.insertion.insert(result, actions: [], method: Defaults[.insertionMethod])
                : await Services.insertion.replaceSelection(with: result)
            guard self.session === session else { return }
            _ = settleAudio(session, keep: false)
            let dictation = Dictation(id: session.id, createdAt: session.startedAt, rawText: instruction, cleanedText: result, app: session.context.app,
                                      duration: duration, mode: .command, source: session.source, outcome: outcome == .inserted ? .formatted : .error)
            remember(dictation)
            lastResult = Result(dictationID: dictation.id, rawText: instruction, insertedText: result, usedLLM: true, outcome: outcome, seconds: (0, 0, 0))
            switch outcome {
            case .inserted: showCompleted(.transformCompleted, session)
            case .notInserted:
                Services.flowBar.show(DictationNotices.pasteFailed(shortcut: pasteLastShortcut)) { _ in
                    Services.insertion.copyToClipboard(result)
                    Services.flowBar.show(DictationNotices.transformCopied()) { _ in }
                }
                end(session, status: .idle)
            case .blockedSecureField: Services.flowBar.show(DictationNotices.blockedSecureInsert()) { _ in }; end(session, status: .idle)
            }
        } catch {
            guard self.session === session else { return }
            fail(session, with: DictationNotices.transformFailed(error))
        }
    }

    /// Auto-learn (§9.4): watches the field for edits of the inserted text, stores what it became, and adds learned words.
    private func watchEdits(of dictation: Dictation) {
        Task { @MainActor in
            guard let edited = await Services.insertion.observeEdits(of: dictation.cleanedText, window: DictationLimits.autoLearnWindow),
                  edited != dictation.cleanedText else { return }
            if var row = Services.history.dictation(dictation.id) {
                row.editedText = edited
                try? Services.history.save(row)
            }
            let entries = AutoLearn.entries(cleaned: dictation.cleanedText, edited: edited, known: Services.history.dictionary)
            guard !entries.isEmpty else { return }
            for entry in entries { try? Services.history.save(entry) }
            Services.flowBar.show(DictationNotices.learned(entries.map { $0.replacement ?? $0.phrase })) { _ in Services.hub.show(.dictionary) }
        }
    }

    // MARK: Ending

    private func showCompleted(_ state: FlowBarState, _ session: Session) {
        Services.flowBar.setState(state)
        end(session, status: .idle, resting: false)
        completedRevert = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DictationLimits.completedStateDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.session == nil else { return }
            Services.flowBar.setState(self.restingState)
        }
    }

    private func fail(_ session: Session, with notice: FlowBarNotification) {
        releaseCapture(session)
        Services.flowBar.setState(.error)
        Services.flowBar.show(notice) { action in
            if action == DictationNotices.openSettings { Permissions.open(.microphone) }
            if action == DictationNotices.openHistory { Services.hub.show(.history) }
            if action == DictationNotices.openModels { Services.hub.showSettings(.models) }
        }
        Services.audio.play(.notificationError)
        end(session, status: .error, resting: false)
        completedRevert = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DictationLimits.completedStateDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.session == nil else { return }
            Services.flowBar.setState(self.restingState)
        }
    }

    private func end(_ session: Session, status: DictationStatus, resting: Bool = true) {
        guard self.session === session else { return }
        releaseCapture(session)
        _ = settleAudio(session, keep: false)
        self.session = nil
        mode = nil
        Services.models.setUserBusy(false)
        if resting { Services.flowBar.setState(restingState) }
        statusSubject.send(status)
    }

    private var restingState: FlowBarState { Defaults[.hideFlowBarPermanently] ? .hidden : .resting }

    // MARK: Transforms (§10, ⌥1–⌥3)

    private func runTransform(_ action: ShortcutAction) {
        let prompt = transformPrompt(for: action)
        guard transform == nil else { return }
        if status.isRecording || status.isBusy {
            Services.flowBar.show(DictationNotices.transformDuringDictation(prompt.name)) { _ in }
            return
        }
        let shortcut = Defaults[.shortcuts].chords(for: action).first?.displayString ?? "⌥1"
        let task = Task { @MainActor [weak self] in
            defer { self?.transform = nil }
            guard let text = await Services.insertion.selectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Services.flowBar.show(DictationNotices.transformNoSelection(shortcut: shortcut)) { _ in }
                return
            }
            Services.flowBar.setState(.transformProcessing(label: prompt.name))
            do {
                let result = try await Services.cleanup.transform(text, instruction: prompt.instruction)
                if result == text {
                    Services.flowBar.show(DictationNotices.transformUnchanged()) { _ in }
                } else if Defaults[.polishAutoPaste] {
                    if await Services.insertion.replaceSelection(with: result) != .inserted {
                        // The result isn't in History: one click puts it on the clipboard.
                        Services.flowBar.show(DictationNotices.transformNotPasted()) { _ in
                            Services.insertion.copyToClipboard(result)
                            Services.flowBar.show(DictationNotices.transformCopied()) { _ in }
                        }
                    }
                } else {
                    Services.insertion.copyToClipboard(result)
                    Services.flowBar.show(DictationNotices.transformCopied()) { _ in }
                }
                Services.flowBar.setState(.transformCompleted)
            } catch {
                Services.flowBar.setState(.error)
                Services.flowBar.show(DictationNotices.transformFailed(error)) { _ in }
                Services.audio.play(.notificationError)
            }
            try? await Task.sleep(nanoseconds: UInt64(DictationLimits.completedStateDuration * 1_000_000_000))
            if let self, self.session == nil { Services.flowBar.setState(self.restingState) }
        }
        transform = (prompt.name, task)
    }

    /// ⌥1 is Polish (the built-in prompt, or a saved one marked built-in); ⌥2 and ⌥3 are the custom prompts in order.
    private func transformPrompt(for action: ShortcutAction) -> TransformPrompt {
        let saved = Services.history.transforms
        let custom = saved.filter { !$0.isBuiltIn }
        switch action {
        case .transformPrompt1 where !custom.isEmpty: return custom[0]
        case .transformPrompt2 where custom.count > 1: return custom[1]
        default: return saved.first(where: \.isBuiltIn) ?? TransformPrompt(name: "Polish", instruction: "polish", isBuiltIn: true)
        }
    }

    // MARK: Notetaker (⌥M, triple tap)

    private func toggleNotetaker() {
        let recorder = Services.meetingRecorder!
        switch recorder.state {
        case .recording: Task { await recorder.stop() }
        case .starting, .stopping: break
        case .idle, .processing:
            Task { @MainActor in
                do { try await recorder.start(nil) } catch {
                    Services.flowBar.show(DictationNotices.notetakerFailed(error)) { _ in }
                }
            }
        }
    }

    // MARK: Helpers

    private func styleProfile(for context: AppContext) -> (style: WritingStyle, level: CleanupLevel) {
        let profile = Defaults[.styleProfile]
        return (profile.style(for: (context.app?.category ?? .other).styleCategory), profile.cleanupLevel)
    }

    private func transcriptionOptions(for context: AppContext) -> TranscriptionOptions {
        var seen: Set<String> = []
        let languages = Defaults[.autoDetectLanguage] ? [] : Defaults[.selectedLanguages].map(SupportedLanguages.base).filter { seen.insert($0).inserted }
        let dictionary = Services.history.dictionary
        let words = (dictionary.filter(\.isStarred) + dictionary.filter { !$0.isStarred }).map { $0.replacement ?? $0.phrase }
        let vocabulary = Array(NSOrderedSet(array: words + context.nearbyWords).compactMap { $0 as? String }.prefix(100))
        return TranscriptionOptions(languages: languages, vocabulary: vocabulary, previousText: Services.history.lastDictation?.displayText)
    }

    private func microphoneNotice(for error: Error) -> FlowBarNotification {
        if let audio = error as? AudioError, audio == .permissionDenied { return DictationNotices.microphoneDenied() }
        return DictationNotices.microphoneFailed(error.localizedDescription)
    }

    private func speechNotice(for error: Error, kept: Bool) -> FlowBarNotification {
        if let speech = error as? SpeechError, case .modelNotInstalled = speech {
            return DictationNotices.gettingReady(fraction: Services.models.readiness(of: Defaults[.asrModelID]), kept: kept)
        }
        return DictationNotices.transcriptionFailed(error.localizedDescription, kept: kept)
    }

    private var pasteLastShortcut: String { Defaults[.shortcuts].chords(for: .pasteLastText).first?.displayString ?? "⌃⌘V" }

    // MARK: Keeping what was said

    /// Ends the session's audio file: kept as `<id>.caf` (its name is returned) or deleted.
    private func settleAudio(_ session: Session, keep: Bool) -> String? {
        guard let recording = session.recording else { return nil }
        session.recording = nil
        return recording.finish(keep: keep)
    }

    /// Saves a finished dictation to History (unless History is off); when it can't be saved, its text stays here for
    /// paste-last and a card says why.
    private func remember(_ dictation: Dictation) {
        guard Defaults[.localDataPolicy] != .never else { lastUnsavedText = dictation.displayText; return }
        do {
            try Services.history.save(dictation)
            lastUnsavedText = nil
        } catch {
            Log.store.error("Couldn't save the dictation: \(error.localizedDescription, privacy: .public)")
            lastUnsavedText = dictation.displayText
            Services.flowBar.show(DictationNotices.historyNotSaved(error, shortcut: pasteLastShortcut)) { _ in }
        }
    }

    /// Keeps a dictation that produced no text in the end (the engine failed, or it was cancelled) as a History row with
    /// its audio, so "Retry transcript" can bring the words back. Taps and Command Mode instructions aren't kept.
    @discardableResult
    private func keepForRetry(_ session: Session, outcome: DictationOutcome) -> Bool {
        guard Defaults[.localDataPolicy] != .never, session.mode != .command, let recording = session.recording,
              recording.duration >= DictationLimits.silentTapDuration, let file = settleAudio(session, keep: true) else { return false }
        let text = session.heard?.text ?? ""
        let row = Dictation(id: session.id, createdAt: session.startedAt, rawText: text, cleanedText: text, app: session.context.app,
                            language: session.heard?.language ?? "en", duration: Double(recording.sampleCount) / Double(AudioClip.sampleRate),
                            mode: session.mode, source: session.source, outcome: outcome, audioFile: file)
        do {
            try Services.history.save(row)
            return true
        } catch {
            Log.store.error("Couldn't keep the dictation for retry: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Dictations a crash, force quit or power loss interrupted: their audio becomes History rows to retry.
    private func recoverInterruptedDictations() {
        var kept = 0
        for row in DictationRecording.recoverLeftovers(except: session?.id) {
            do { try Services.history.save(row); kept += 1 } catch {
                Log.store.error("Couldn't keep an interrupted dictation: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard kept > 0 else { return }
        Log.app.info("Recovered \(kept) interrupted dictation(s)")
        Services.flowBar.show(DictationNotices.recovered(count: kept)) { _ in Services.hub.show(.history) }
    }

    // MARK: Retry

    /// Runs beside the dictation state machine, so the hotkey still starts a dictation meanwhile (which then goes first
    /// on the speech engine).
    public func retryTranscription(_ id: UUID) async throws {
        guard status.canStart else { throw DictationRetryError.busy }
        guard var row = Services.history.dictation(id) else { throw StoreError.notFound(id) }
        guard let file = row.audioFile, let samples = DictationRecording.samples(of: file), !samples.isEmpty else {
            throw DictationRetryError.audioUnavailable
        }
        let context = AppContext(app: row.app)
        let transcript = try await Services.speech.transcribe(AudioClip(samples: samples), options: transcriptionOptions(for: context), priority: .dictation)
        let style = styleProfile(for: context)
        let format = row.app.flatMap { Defaults[.appTranscriptionFormats][$0.bundleID] } ?? Defaults[.defaultTranscriptionFormat]
        let output = await Services.cleanup.clean(CleanupInput(transcript: transcript, context: context, style: style.style, level: style.level,
                                                               format: format, dictionary: Services.history.dictionary,
                                                               snippets: Services.history.snippets),
                                                  budget: DictationLimits.cleanupBudgetLong)
        row.rawText = transcript.text
        row.cleanedText = output.text.isEmpty ? transcript.text : output.text
        row.language = transcript.language
        row.wordCount = Dictation.countWords(row.cleanedText)
        row.usesRawText = false
        row.outcome = output.usedLLM ? .formatted : output.skipReason == .clientDisabled ? .rawTranscript : .fallback
        try Services.history.save(row)
    }
}

/// One dictation from key-down to insertion.
@MainActor
final class Session {
    /// The History row's id, and the name of its audio file.
    let id = UUID()
    var mode: DictationMode
    let source: DictationSource
    let context: AppContext
    let startedAt: Date
    var listeningSince: Date?
    /// Command Mode: the selected text at the start.
    var selection: String?
    /// "Getting ready…": waiting for the speech model to install.
    var preparing = false
    var listening = false
    var stopped = false
    var cancelled = false
    var holdsMicrophone = false
    var partial = ""
    /// The audio as it is recorded (nil when History is off or the file couldn't be created).
    var recording: DictationRecording?
    /// The final transcript once recognition finished (kept with a dictation cancelled while it was being processed).
    var heard: Transcript?
    var lastFrameAt: Date?
    var speechError: Error?
    var clips: AsyncStream<AudioClip>.Continuation?
    var frames: Task<Void, Never>?
    var transcription: Task<Transcript?, Never>?
    var watchdog: Task<Void, Never>?
    var limit: Task<Void, Never>?
    var finishing: Task<Void, Never>?

    init(mode: DictationMode, source: DictationSource, context: AppContext, startedAt: Date) {
        self.mode = mode; self.source = source; self.context = context; self.startedAt = startedAt
    }
}

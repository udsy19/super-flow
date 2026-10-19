import AppKit
import Combine
import Foundation
import SuperFlowCore

public enum MeetingRecorderError: LocalizedError, Equatable {
    case alreadyRecording
    /// Too little free space to record (`MeetingRecorder.minimumFreeSpace`).
    case storageFull
    /// The meeting is being recorded or processed right now.
    case busy
    /// "Retry transcript" found no saved audio for the meeting.
    case noAudio

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: "The Notetaker is already recording."
        case .storageFull: "Your Mac is almost out of space. Free some space to record a meeting."
        case .busy: "This meeting is still being processed."
        case .noAudio: "The audio of this meeting is no longer available."
        }
    }
}

/// Dual-track meeting recording (behaviour.md §20.4–§20.7, local-models.md §8.2–§8.4): the microphone ("You") and
/// system audio ("Them") are written to disk as they arrive, cut into utterances, transcribed with the shared speech
/// engine at meeting priority, and saved to the store every few seconds. Stopping runs the post-meeting stages in the
/// background: the last transcriptions, speaker split of the "Them" track, final audio files, and the notes.
@MainActor
public final class MeetingRecorder: MeetingRecording {
    public static let shared = MeetingRecorder()

    /// The processing stages the hub shows, in order (strings.md `hub_meeting_flow_summary_loading_*`).
    public enum Stage {
        public static let processingAudio = "Processing audio..."
        public static let transcribing = "Transcribing audio..."
        public static let refining = "Refining content..."
        public static let summarizing = "Summarizing meeting..."
        public static let generating = "Generating summary..."
    }

    /// Default titles that the generated title may replace.
    nonisolated static let untitledTitles: Set<String> = [MeetingExport.untitled, "Untitled meeting"]

    /// Seconds between saves of the live transcript (a crash loses at most this much text; the audio is never lost).
    public var persistInterval: TimeInterval = 5
    /// Free space below which a recording stops by itself and keeps everything so far (about an hour of both tracks as
    /// raw chunks, and room to encode the final files); a recording doesn't start below it.
    public var minimumFreeSpace: Int64 = 250 << 20
    /// Free bytes on the volume that holds meeting audio; the self-test substitutes its own.
    public var freeSpace: () -> Int64 = { SuperFlowPaths.freeSpace(at: SuperFlowPaths.meetingAudio) }
    /// How often a recording checks the free space and that the microphone still delivers audio.
    public var monitorInterval: TimeInterval = 5
    /// No microphone frame for this long: the microphone is restarted once (its device went away or changed).
    public var micSilenceLimit: TimeInterval = 10

    private let stateSubject = CurrentValueSubject<MeetingRecordingState, Never>(.idle)
    private var liveSubscribers: [UUID: AsyncStream<TranscriptSegment>.Continuation] = [:]
    private var session: RecordingSession?
    private var processing: [UUID: Task<Void, Never>] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public init() {
        // Sleep and fast user switching end the recording properly (§20.4.5); a quit saves the transcript so far (the
        // audio is already on disk and the next launch finishes the meeting).
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.macWillPause() }
            }))
        }
        let app = NotificationCenter.default
        observers.append((app, app.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, let session = self.session { self.persist(session) } }
        }))
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    public var state: MeetingRecordingState { stateSubject.value }
    public var stateChanges: AnyPublisher<MeetingRecordingState, Never> { stateSubject.eraseToAnyPublisher() }

    /// Every access is a new subscription to the segments that follow.
    public var liveSegments: AsyncStream<TranscriptSegment> {
        AsyncStream { continuation in
            let id = UUID()
            liveSubscribers[id] = continuation
            continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.liveSubscribers[id] = nil } }
        }
    }

    /// The meeting being recorded, with its transcript so far.
    public var currentMeeting: Meeting? { session?.meeting }
    /// The detector's id of the meeting being recorded (auto-end matches `.ended` against it).
    public var detectedMeetingID: String? { session?.detectedID }

    // MARK: Start

    @discardableResult
    public func start(_ detected: DetectedMeeting?) async throws -> Meeting {
        guard state.acceptsNewRecording else { throw MeetingRecorderError.alreadyRecording }
        guard freeSpace() >= minimumFreeSpace else { throw MeetingRecorderError.storageFull }
        let previous = state
        setState(.starting)
        let event = detected?.calendarEvent
        let meeting = Meeting(title: event?.title ?? detected?.title ?? MeetingExport.untitled, platform: detected?.platform ?? .other,
                              calendarEventID: event?.id, participants: event?.attendees ?? [])
        let session = RecordingSession(meeting: meeting, detectedID: detected?.id, folder: SuperFlowPaths.meetingAudio(meeting.id))
        session.lock = WriterLock(session.folder.appendingPathComponent(RecordingSession.lockName))
        session.vocabulary = vocabulary(for: meeting)
        self.session = session
        Task { await Self.prepareSpeechEngine() }
        Task { await Self.prepareNotesModel() }
        Services.flowBar?.setMeetingPhase(.pending)

        // Subscribe before capture starts so the first frames are kept.
        let frames = Services.audio.frames
        session.frameTask = Task { [weak self] in
            for await frame in frames {
                guard let self, self.session === session else { return }
                await self.handle(frame, in: session)
            }
        }
        var micError: Error?
        do {
            try await Services.audio.startMicrophone()
            session.holdsMicrophone = true
        } catch { micError = error }
        var systemError: Error?
        do {
            try await Services.audio.startSystemAudio()
            session.holdsSystemAudio = true
        } catch {
            Log.meetings.error("System audio isn't being captured: \(error.localizedDescription, privacy: .public)")
            if let micError { return try abandon(session, restoring: previous, error: micError) }
            systemError = error
        }
        if let micError { Log.meetings.error("Microphone isn't being captured: \(micError.localizedDescription, privacy: .public)") }
        do { try Services.meetings.save(meeting) } catch { return try abandon(session, restoring: previous, error: error) }
        if systemError != nil {
            // Mic only: say so instead of quietly recording half the meeting.
            let method = Services.audio.systemAudioMethod
            Services.flowBar?.show(MeetingNotices.systemAudioOff(canTurnOn: method != .unsupported)) { _ in
                Permissions.open(method == .screenCaptureKit ? .screenRecording : .audioCapture)
            }
        }

        Services.models?.setUserBusy(true)
        Services.flowBar?.setMeetingPhase(.recording(wordCount: 0, startedAt: meeting.startedAt))
        if Defaults[.notetakerOpenWindowOnRecord] { Services.hub?.showNotepad(for: meeting.id) }
        let limit = TimeInterval(Defaults[.notetakerMaxRecordingLength])
        session.limitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            guard !Task.isCancelled, let self, self.session === session else { return }
            Log.meetings.info("Maximum recording length reached")
            await self.stop()
        }
        session.monitorTask = Task { [weak self] in await self?.monitor(session) }
        setState(.recording(meetingID: meeting.id))
        Log.meetings.info("Recording meeting \(meeting.id, privacy: .public)")
        return meeting
    }

    /// While recording: stops before the disk fills up (everything so far is kept), and restarts a microphone that
    /// went quiet because its device went away or changed, saying so when that doesn't bring it back.
    private func monitor(_ session: RecordingSession) async {
        var micRestartedAt: Date?
        while !Task.isCancelled, self.session === session {
            try? await Task.sleep(nanoseconds: UInt64(monitorInterval * 1_000_000_000))
            guard !Task.isCancelled, self.session === session, case .recording = state else { return }
            if freeSpace() < minimumFreeSpace {
                await stopForStorage(session)
                return
            }
            guard session.holdsMicrophone else { continue }
            let lastMic = session.lastFrameAt[.mic] ?? session.startedAt
            guard Date().timeIntervalSince(lastMic) > micSilenceLimit else { micRestartedAt = nil; continue }
            if let restarted = micRestartedAt {
                if Date().timeIntervalSince(restarted) > micSilenceLimit, !session.reportedMicLoss {
                    session.reportedMicLoss = true
                    Services.flowBar?.show(MeetingNotices.microphoneLost()) { _ in Permissions.open(.microphone) }
                }
                continue
            }
            Log.meetings.info("No microphone audio for \(Int(self.micSilenceLimit)) s; restarting the microphone")
            micRestartedAt = Date()
            Services.audio.stopMicrophone()
            do { try await Services.audio.startMicrophone() } catch {
                Log.meetings.error("The microphone didn't come back: \(error.localizedDescription, privacy: .public)")
                session.holdsMicrophone = false
                session.reportedMicLoss = true
                Services.flowBar?.show(MeetingNotices.microphoneLost()) { _ in Permissions.open(.microphone) }
            }
        }
    }

    /// The disk is (nearly) full: stop now, while the chunks written so far can still be encoded and the row saved.
    private func stopForStorage(_ session: RecordingSession) async {
        guard self.session === session, case .recording(let id) = state else { return }
        Log.meetings.error("Stopping the recording: the disk is almost full")
        Services.flowBar?.show(MeetingNotices.storageFull()) { _ in Services.hub?.showMeeting(id) }
        await stop()
    }

    /// The Mac is going to sleep or the user session is switching away: finish the recording rather than leave a gap.
    private func macWillPause() {
        guard let session, case .recording(let id) = state else { return }
        Log.meetings.info("The Mac is going to sleep; stopping the recording")
        persist(session)
        Services.flowBar?.show(MeetingNotices.stoppedForSleep()) { _ in Services.hub?.showMeeting(id) }
        Task { await stop() }
    }

    /// Nothing could be captured or saved: undo the start and report why.
    private func abandon(_ session: RecordingSession, restoring previous: MeetingRecordingState, error: Error) throws -> Meeting {
        releaseCapture(session)
        self.session = nil
        try? FileManager.default.removeItem(at: session.folder)
        Services.flowBar?.setMeetingPhase(nil)
        setState(previous)
        throw error
    }

    private func vocabulary(for meeting: Meeting) -> [String] {
        let dictionary = (Services.history?.dictionary ?? []).sorted { $0.isStarred && !$1.isStarred }.map { $0.replacement ?? $0.phrase }
        return Array((meeting.participants.map(\.name).filter { !$0.isEmpty } + dictionary).prefix(100))
    }

    // MARK: Live

    private func handle(_ frame: AudioFrame, in session: RecordingSession) async {
        let origin = session.origin ?? frame.time
        session.origin = origin
        session.lastFrameAt[frame.channel] = Date()
        guard let channel = session.channels[frame.channel] else { return }
        // Dictated words never enter the meeting (local-models.md §8.3): the mic is muted while a dictation records.
        let muted = frame.channel == .mic && (Services.dictation?.status.isRecording ?? false)
        let appended = await channel.append(frame.samples, at: frame.time - origin, muted: muted)
        for utterance in appended.utterances { enqueue(utterance, channel: frame.channel, in: session) }
        if appended.writeFailed { await stopForStorage(session) }
    }

    /// Transcribes utterances of one channel in order, one at a time.
    private func enqueue(_ utterance: Utterance, channel: AudioChannel, in session: RecordingSession) {
        let previous = session.transcription[channel]
        session.transcription[channel] = Task { [weak self] in
            await previous?.value
            guard let self, !session.discarded else { return }
            let recognition = await self.recognize(utterance, channel: channel, vocabulary: session.vocabulary)
            if case .failed = recognition { session.recognitionFailures += 1 }
            guard case .segment(let segment) = recognition, !session.discarded else { return }
            session.meeting.segments.append(segment)
            session.wordCount += Dictation.countWords(segment.text)
            self.publish(segment)
            if self.session === session, case .recording = self.state {
                Services.flowBar?.setMeetingPhase(.recording(wordCount: session.wordCount, startedAt: session.meeting.startedAt))
            }
            self.schedulePersist(session)
            self.scheduleRollingMap(session)
        }
    }

    /// What the engine made of one utterance: a final segment, no speech (its VAD, or empty text), or an error (the
    /// engine isn't ready or failed: the audio stays on disk and is transcribed again after the meeting).
    private enum Recognition {
        case segment(TranscriptSegment)
        case noSpeech
        case failed(Error)
    }

    private func recognize(_ utterance: Utterance, channel: AudioChannel, vocabulary: [String]) async -> Recognition {
        guard let speech = Services.speech else { return .failed(SpeechError.engineUnavailable("No speech engine.")) }
        let clip = AudioClip(samples: utterance.samples, startTime: utterance.start)
        do {
            let transcript = try await speech.transcribe(clip, options: TranscriptionOptions(vocabulary: vocabulary), priority: .meeting)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .noSpeech : .segment(TranscriptSegment(channel: channel, start: utterance.start, end: utterance.end, text: text))
        } catch SpeechError.noSpeech {
            return .noSpeech
        } catch {
            Log.meetings.error("Meeting transcription failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error)
        }
    }

    private func publish(_ segment: TranscriptSegment) {
        for continuation in liveSubscribers.values { continuation.yield(segment) }
    }

    private func schedulePersist(_ session: RecordingSession) {
        guard session.persistTask == nil else { return }
        let interval = persistInterval
        session.persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            session.persistTask = nil
            guard !Task.isCancelled else { return }
            self?.persist(session)
        }
    }

    /// Saves what the recorder owns (transcript, tracks, end time) onto the stored row, keeping edits made elsewhere
    /// meanwhile (title, the user's notes, folder, participants).
    private func persist(_ session: RecordingSession) {
        guard !session.discarded else { return }
        update(session.meeting.id) { row in
            row.segments = session.meeting.segments.sorted { $0.start < $1.start }
            row.endedAt = session.meeting.endedAt
        }
    }

    /// The rolling "map" of local-models.md §8.6: each chunk of settled transcript is turned into notes while the meeting
    /// goes on, so the summary is ready seconds after it ends. Runs one chunk at a time, only when the notes model is loaded.
    private func scheduleRollingMap(_ session: RecordingSession) {
        guard session.mapTask == nil, let summarizer = Services.summarizer as? MeetingSummarizer, summarizer.isModelReady,
              let latest = session.meeting.segments.map(\.end).max() else { return }
        // Segments that can no longer be overtaken by a slower channel; the last chunk is still growing.
        let settled = session.meeting.segments.filter { $0.end < latest - 30 }
        let chunks = TranscriptChunker.chunks(settled, wordBudget: summarizer.chunkWordBudget).dropLast()
        guard chunks.count > session.mappedChunks else { return }
        let chunk = chunks[chunks.startIndex + session.mappedChunks]
        session.mapTask = Task { [weak self] in
            do { _ = try await summarizer.map(chunk) } catch {
                Log.meetings.error("Rolling notes failed: \(error.localizedDescription, privacy: .public)")
            }
            session.mappedChunks += 1
            session.mapTask = nil
            if !session.discarded, self?.session === session { self?.scheduleRollingMap(session) }
        }
    }

    // MARK: Notes and markers

    public func appendNote(_ text: String) {
        guard let id = session?.meeting.id else { return }
        update(id) { row in
            let separator = row.notes.isEmpty || row.notes.hasSuffix("\n") ? "" : "\n"
            row.notes += separator + text
        }
    }

    public func addMarker(_ label: String) {
        guard let meeting = session?.meeting else { return }
        let marker = MeetingMarker(time: Date().timeIntervalSince(meeting.startedAt), label: label.trimmingCharacters(in: .whitespacesAndNewlines))
        update(meeting.id) { $0.markers.append(marker) }
    }

    // MARK: Stop and discard

    public func stop() async {
        guard let session, case .recording(let id) = state else { return }
        setState(.stopping(meetingID: id))
        Services.flowBar?.setMeetingPhase(.stopping)
        session.limitTask?.cancel()
        session.monitorTask?.cancel()
        releaseCapture(session)
        for (channel, recorder) in session.channels {
            if let utterance = await recorder.finish() { enqueue(utterance, channel: channel, in: session) }
        }
        session.meeting.endedAt = Date()
        session.persistTask?.cancel()
        persist(session)
        self.session = nil
        Services.models?.setUserBusy(false)
        Services.flowBar?.setMeetingPhase(nil)
        Log.meetings.info("Stopped meeting \(id, privacy: .public)")
        setState(.processing(meetingID: id, stage: Stage.processingAudio))
        processing[id] = Task { [weak self] in await self?.process(id, folder: session.folder, live: session) }
    }

    // MARK: Retry

    public func retryTranscript(of id: UUID) async throws {
        try ensureIdle(id)
        let folder = SuperFlowPaths.meetingAudio.appendingPathComponent(id.uuidString)
        guard AudioChannel.allCases.contains(where: { !MeetingAudioFiles.samples(folder: folder, channel: $0, fromSample: 0).isEmpty }) else {
            throw MeetingRecorderError.noAudio
        }
        var failure: Error?
        let task = Task { [weak self] in
            guard let self else { return }
            failure = await self.process(id, folder: folder, live: nil, whole: true)
        }
        processing[id] = task
        await task.value
        if let failure { throw failure }
    }

    public func regenerateNotes(of id: UUID) async throws {
        try ensureIdle(id)
        var failure: Error?
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishedProcessing(id) }
            await Self.prepareNotesModel()
            do { try await self.writeNotes(id) } catch { failure = error }
        }
        processing[id] = task
        await task.value
        if let failure { throw failure }
    }

    /// A retry runs only on a meeting that is neither being recorded nor processed.
    private func ensureIdle(_ id: UUID) throws {
        guard Services.meetings.meeting(id) != nil else { throw StoreError.notFound(id) }
        guard session?.meeting.id != id, processing[id] == nil else { throw MeetingRecorderError.busy }
    }

    public func discard() async {
        if let session {
            session.discarded = true
            session.limitTask?.cancel()
            session.monitorTask?.cancel()
            releaseCapture(session)
            for recorder in session.channels.values { _ = await recorder.finish() }
            for task in session.transcription.values { task.cancel() }
            session.mapTask?.cancel()
            session.persistTask?.cancel()
            self.session = nil
            Services.models?.setUserBusy(false)
            Services.flowBar?.setMeetingPhase(nil)
            delete(session.meeting.id)
        } else if case .processing(let id, _) = state {
            processing[id]?.cancel()
            processing[id] = nil
            delete(id)
        }
        if session == nil { setState(processing.isEmpty ? .idle : state) }
    }

    /// Lets go of the captures this recording started (the microphone is shared with dictation and reference-counted)
    /// and ends its frame subscription.
    private func releaseCapture(_ session: RecordingSession) {
        session.lock?.release()
        session.lock = nil
        try? FileManager.default.removeItem(at: session.folder.appendingPathComponent(RecordingSession.lockName))
        if session.holdsMicrophone { Services.audio.stopMicrophone() }
        if session.holdsSystemAudio { Services.audio.stopSystemAudio() }
        session.holdsMicrophone = false
        session.holdsSystemAudio = false
        session.frameTask?.cancel()
    }

    private func delete(_ id: UUID) {
        do { try Services.meetings.deleteMeeting(id) } catch StoreError.notFound {} catch {
            Log.meetings.error("Couldn't delete meeting \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        try? FileManager.default.removeItem(at: SuperFlowPaths.meetingAudio.appendingPathComponent(id.uuidString))
        Log.meetings.info("Discarded meeting \(id, privacy: .public)")
    }

    /// Waits for the post-meeting stages of every stopped or recovered meeting.
    public func waitForProcessing() async {
        while let task = processing.values.first { await task.value }
    }

    // MARK: After the meeting

    /// The post-meeting stages: the last transcriptions (or, after a crash or for "Retry transcript", the audio from disk),
    /// speakers, final audio files, notes. Returns why nothing could be transcribed when `whole` found no speech engine.
    @discardableResult
    private func process(_ id: UUID, folder: URL, live: RecordingSession?, whole: Bool = false) async -> Error? {
        defer { finishedProcessing(id) }
        stage(id, Stage.processingAudio)

        stage(id, Stage.transcribing)
        var failure: Error?
        if let live {
            for task in live.transcription.values { await task.value }
            await live.mapTask?.value
            persist(live)
            // Utterances the engine failed on during the meeting: their audio is on disk, so transcribe it all again.
            if live.recognitionFailures > 0 { failure = await transcribeFromDisk(id, folder: folder, whole: true) }
        } else {
            failure = await transcribeFromDisk(id, folder: folder, whole: whole)
        }
        guard !Task.isCancelled, Services.meetings.meeting(id) != nil else { return failure }

        stage(id, Stage.refining)
        let system = await Task.detached(priority: .utility) { MeetingAudioFiles.samples(folder: folder, channel: .system) }.value
        var voices: [TranscriptSegment] = []
        if Defaults[.notetakerAttributeNamesEnabled], !system.isEmpty, let speech = Services.speech {
            do { voices = try await speech.diarize(AudioClip(samples: system)) } catch {
                Log.meetings.error("Speaker split failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard !Task.isCancelled else { return failure }
        update(id) { $0.assignSpeakers(voices: voices) }
        let tracks = await Task.detached(priority: .utility) { () -> [AudioTrack] in
            AudioChannel.allCases.compactMap { channel in
                do { return try MeetingAudioFiles.finalize(folder: folder, channel: channel) } catch {
                    Log.meetings.error("Couldn't write the \(channel.rawValue, privacy: .public) track: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }.value
        guard !Task.isCancelled else { return failure }
        // A track that couldn't be encoded keeps its chunks (and its place in the list) for the next attempt.
        update(id) { row in row.tracks = tracks.isEmpty ? row.tracks : tracks }

        do { try await writeNotes(id) } catch {
            Log.meetings.info("No notes for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return failure
    }

    private func finishedProcessing(_ id: UUID) {
        processing[id] = nil
        if session == nil, processing.isEmpty {
            setState(.idle)
            if !Defaults[.keepModelsInMemory] { Services.cleanup?.unload(role: .notes) }
        }
    }

    /// The notes stages ("Summarizing meeting…", "Generating summary…"); throws why there are none (no model, too short).
    private func writeNotes(_ id: UUID) async throws {
        guard let summarizer = Services.summarizer else { throw MeetingNotesError.modelNotReady }
        guard let meeting = Services.meetings.meeting(id) else { throw StoreError.notFound(id) }
        stage(id, Stage.summarizing)
        if let summarizer = summarizer as? MeetingSummarizer { try await summarizer.mapChunks(of: meeting) }
        stage(id, Stage.generating)
        let summary = try await summarizer.summarize(Services.meetings.meeting(id) ?? meeting)
        guard !Task.isCancelled else { throw CancellationError() }
        update(id) { row in
            row.summary = summary
            if row.calendarEventID == nil, Self.untitledTitles.contains(row.title), !summary.title.isEmpty { row.title = summary.title }
        }
        let existing = Set(Services.meetings.actionItems.filter { $0.meetingID == id }.map(\.text))
        for item in summary.actionItems where !existing.contains(item.text) { try Services.meetings.save(item) }
    }

    private func stage(_ id: UUID, _ stage: String) {
        if session == nil { setState(.processing(meetingID: id, stage: stage)) }
    }

    /// Loads the dictation engine when none is loaded (meetings share it, local-models.md §8.3). Utterances that arrive
    /// before it is ready fail and are logged; their audio stays on disk.
    private static func prepareSpeechEngine() async {
        guard let speech = Services.speech, speech.activeEngineID == nil else { return }
        do { try await speech.prepare(modelID: Defaults[.asrModelID]) } catch {
            Log.meetings.error("No speech engine for the meeting: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads the notes model (`Defaults[.notesModelID]`, local-models.md §8.6) when it is installed, so the rolling map
    /// can run during the meeting and the summary follows seconds after it ends.
    private static func prepareNotesModel() async {
        guard let cleanup = Services.cleanup, !cleanup.isModelReady(for: .notes),
              Services.models?.state(of: Defaults[.notesModelID]) == .installed else { return }
        do { try await cleanup.prepare(modelID: Defaults[.notesModelID], role: .notes) } catch {
            Log.meetings.error("No notes model for the meeting: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Transcribes recorded audio from disk: after a crash only what follows the last saved segment of each channel;
    /// with `whole`, everything (the result replaces the transcript unless the engine failed on more of it than before).
    /// Returns the engine's error when it couldn't transcribe anything.
    private func transcribeFromDisk(_ id: UUID, folder: URL, whole: Bool) async -> Error? {
        guard let meeting = Services.meetings.meeting(id) else { return nil }
        await Self.prepareSpeechEngine()
        await Self.prepareNotesModel()
        let vocabulary = vocabulary(for: meeting)
        var added: [TranscriptSegment] = []
        var failures: [Error] = []
        var attempts = 0
        for channel in AudioChannel.allCases {
            let lastSaved = meeting.segments.filter { $0.channel == channel }.map(\.end).max() ?? 0
            let from = whole ? 0 : Int(lastSaved * Double(AudioClip.sampleRate))
            let samples = await Task.detached(priority: .utility) { MeetingAudioFiles.samples(folder: folder, channel: channel, fromSample: from) }.value
            var segmenter = SpeechSegmenter(startSample: from)
            let utterances = segmenter.append(samples) + [segmenter.flush()].compactMap { $0 }
            for utterance in utterances {
                attempts += 1
                switch await recognize(utterance, channel: channel, vocabulary: vocabulary) {
                case .segment(let segment): added.append(segment)
                case .noSpeech: break
                case .failed(let error): failures.append(error)
                }
            }
        }
        if whole {
            let before = meeting.segments.filter(\.isFinal).reduce(0) { $0 + Dictation.countWords($1.text) }
            let after = added.reduce(0) { $0 + Dictation.countWords($1.text) }
            if failures.isEmpty || after > before { update(id) { $0.segments = added.sorted { $0.start < $1.start } } }
        } else if !added.isEmpty {
            update(id) { $0.segments = ($0.segments + added).sorted { $0.start < $1.start } }
        }
        return attempts > 0 && failures.count == attempts ? failures.first : nil
    }

    /// Finishes recordings a crash or quit interrupted: their chunk files are still in `Audio/Meetings/<id>/`. Each gets
    /// an end time, the transcript of its untranscribed tail, speakers, final audio files and notes, like a normal stop.
    /// Audio whose row is gone (a store rebuilt from a damaged file) becomes a "Recovered recording from …" meeting:
    /// recorded audio is never deleted here.
    public func recoverInterruptedMeetings() {
        let fm = FileManager.default
        let root = SuperFlowPaths.meetingAudio
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for folder in folders {
            let lock = folder.appendingPathComponent(RecordingSession.lockName)
            guard let id = UUID(uuidString: folder.lastPathComponent), id != session?.meeting.id, processing[id] == nil else { continue }
            // Another running copy of Super Flow is recording into it: not ours to finish.
            guard !WriterLock.isHeld(lock) else { continue }
            try? fm.removeItem(at: lock)
            let chunks = AudioChannel.allCases.contains { !ChunkedTrackWriter.chunks(in: folder, channel: $0).isEmpty }
            var meeting: Meeting
            if let row = Services.meetings.meeting(id) {
                guard chunks else { continue }
                meeting = row
            } else {
                // Less than a second of audio: nothing anyone could want.
                let duration = MeetingAudioFiles.recordedDuration(folder: folder)
                guard duration >= 1 else {
                    try? fm.removeItem(at: folder)
                    continue
                }
                let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date().addingTimeInterval(-duration)
                meeting = Meeting(id: id, title: MeetingNotices.recoveredTitle(created), startedAt: created)
                Log.meetings.info("Recovering audio without a meeting row: \(id, privacy: .public)")
            }
            if meeting.endedAt == nil {
                meeting.endedAt = meeting.startedAt.addingTimeInterval(MeetingAudioFiles.recordedDuration(folder: folder))
            }
            do { try Services.meetings.save(meeting) } catch {
                Log.meetings.error("Couldn't save the recovered meeting \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            Log.meetings.info("Recovering interrupted meeting \(id, privacy: .public)")
            Services.flowBar?.show(MeetingNotices.recovered(startedAt: meeting.startedAt)) { _ in Services.hub?.showMeeting(id) }
            if session == nil { setState(.processing(meetingID: id, stage: Stage.processingAudio)) }
            processing[id] = Task { [weak self] in await self?.process(id, folder: folder, live: nil) }
        }
    }

    // MARK: Editing

    /// "Update everywhere" (§20.7.3); the meeting's action items follow the new name.
    public func renameSpeaker(_ speakerID: UUID, to name: String, inMeeting id: UUID) throws {
        guard let meeting = Services.meetings.meeting(id), let speaker = meeting.speakers.first(where: { $0.id == speakerID }) else {
            throw StoreError.notFound(id)
        }
        let previous = speaker.displayName
        var edited = meeting
        edited.renameSpeaker(speakerID, to: name)
        try Services.meetings.save(edited)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != previous else { return }
        for var item in Services.meetings.actionItems where item.meetingID == id && item.owner == previous {
            item.owner = trimmed
            try Services.meetings.save(item)
        }
    }

    /// "Update only this block" (§20.7.3).
    public func assignBlock(containing segmentID: UUID, to name: String, inMeeting id: UUID) throws {
        guard var meeting = Services.meetings.meeting(id) else { throw StoreError.notFound(id) }
        meeting.assignBlock(containing: segmentID, to: name)
        try Services.meetings.save(meeting)
    }

    /// Loads the stored row, applies a change and saves it; nothing happens when the row is gone (deleted meanwhile).
    private func update(_ id: UUID, _ change: (inout Meeting) -> Void) {
        guard var row = Services.meetings.meeting(id) else { return }
        change(&row)
        do { try Services.meetings.save(row) } catch {
            Log.meetings.error("Couldn't save meeting \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Retention

    @discardableResult public func pruneAudio(now: Date) -> [UUID] {
        let days = Defaults[.meetingAudioRetentionDays]
        guard let cutoff = RetentionPolicy.cutoff(days: days, now: now) else { return [] }
        var pruned: [UUID] = []
        for var meeting in Services.meetings.meetingsWithAudio(before: cutoff)
        where RetentionPolicy.shouldDeleteAudio(of: meeting, audioDays: days, now: now) && processing[meeting.id] == nil {
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

    private func setState(_ new: MeetingRecordingState) {
        if stateSubject.value != new { stateSubject.send(new) }
    }
}

/// One recording in progress.
@MainActor
final class RecordingSession {
    var meeting: Meeting
    let detectedID: String?
    let folder: URL
    let channels: [AudioChannel: ChannelRecorder]
    var vocabulary: [String] = []
    /// Host time of the first frame: the zero of every timestamp in the meeting.
    var origin: TimeInterval?
    var wordCount = 0
    var discarded = false
    var holdsMicrophone = false
    var holdsSystemAudio = false
    var mappedChunks = 0
    /// When the recording began, for the microphone watchdog before the first frame.
    let startedAt = Date()
    /// `lockName` in the folder, held while recording (`WriterLock`).
    static let lockName = "recording.lock"
    var lock: WriterLock?
    /// When each channel last delivered a frame.
    var lastFrameAt: [AudioChannel: Date] = [:]
    var reportedMicLoss = false
    /// Utterances the engine failed on (not ready, or an error): the meeting is transcribed again from disk afterwards.
    var recognitionFailures = 0
    var frameTask: Task<Void, Never>?
    var limitTask: Task<Void, Never>?
    var monitorTask: Task<Void, Never>?
    var persistTask: Task<Void, Never>?
    var mapTask: Task<Void, Never>?
    var transcription: [AudioChannel: Task<Void, Never>] = [:]

    init(meeting: Meeting, detectedID: String?, folder: URL) {
        self.meeting = meeting
        self.detectedID = detectedID
        self.folder = folder
        channels = Dictionary(uniqueKeysWithValues: AudioChannel.allCases.map { ($0, ChannelRecorder(folder: folder, channel: $0)) })
    }
}

/// One channel's disk writer and segmenter, off the main actor.
actor ChannelRecorder {
    private let writer: ChunkedTrackWriter
    private var segmenter: SpeechSegmenter
    private var finished = false
    private var reportedWriteError = false

    init(folder: URL, channel: AudioChannel) {
        writer = ChunkedTrackWriter(folder: folder, channel: channel)
        segmenter = SpeechSegmenter(startSample: writer.totalSamples)
    }

    /// Writes a block that starts `offset` seconds into the recording, filling any gap before it with silence so both
    /// tracks stay on the meeting's timeline; returns the utterances that closed, and whether the disk refused the block
    /// (full, or the folder went away): the recording then stops with what it has.
    func append(_ samples: [Float], at offset: TimeInterval, muted: Bool) -> (utterances: [Utterance], writeFailed: Bool) {
        guard !finished else { return ([], false) }
        var block = muted ? [Float](repeating: 0, count: samples.count) : samples
        let gap = Int(offset * Double(AudioClip.sampleRate)) - writer.totalSamples
        if gap > AudioClip.sampleRate / 10, gap < 3 * 3600 * AudioClip.sampleRate {
            block = [Float](repeating: 0, count: gap) + block
        }
        var failed = false
        do { try writer.append(block) } catch {
            if !reportedWriteError { Log.meetings.error("Couldn't write meeting audio: \(error.localizedDescription, privacy: .public)") }
            reportedWriteError = true
            failed = true
        }
        return (segmenter.append(block), failed)
    }

    func finish() -> Utterance? {
        guard !finished else { return nil }
        finished = true
        writer.close()
        return segmenter.flush()
    }
}

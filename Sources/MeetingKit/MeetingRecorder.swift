import Combine
import Foundation
import SuperFlowCore

public enum MeetingRecorderError: LocalizedError, Equatable {
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: "The Notetaker is already recording."
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
    nonisolated static let untitledNote = "Untitled note"
    nonisolated static let untitledTitles: Set<String> = [untitledNote, "Untitled meeting"]

    /// Seconds between saves of the live transcript (a crash loses at most this much text; the audio is never lost).
    public var persistInterval: TimeInterval = 5

    private let stateSubject = CurrentValueSubject<MeetingRecordingState, Never>(.idle)
    private var liveSubscribers: [UUID: AsyncStream<TranscriptSegment>.Continuation] = [:]
    private var session: RecordingSession?
    private var processing: [UUID: Task<Void, Never>] = [:]

    public init() {}

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
        let previous = state
        setState(.starting)
        let event = detected?.calendarEvent
        let meeting = Meeting(title: event?.title ?? detected?.title ?? Self.untitledNote, platform: detected?.platform ?? .other,
                              calendarEventID: event?.id, participants: event?.attendees ?? [])
        let session = RecordingSession(meeting: meeting, detectedID: detected?.id, folder: SuperFlowPaths.meetingAudio(meeting.id))
        session.vocabulary = vocabulary(for: meeting)
        self.session = session
        Task { await Self.prepareSpeechEngine() }
        Services.flowBar?.setState(.meeting(.pending))

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
        do {
            try await Services.audio.startSystemAudio()
            session.holdsSystemAudio = true
        } catch {
            Log.meetings.error("System audio isn't being captured: \(error.localizedDescription, privacy: .public)")
            if let micError { return try abandon(session, restoring: previous, error: micError) }
        }
        if let micError { Log.meetings.error("Microphone isn't being captured: \(micError.localizedDescription, privacy: .public)") }
        do { try Services.meetings.save(meeting) } catch { return try abandon(session, restoring: previous, error: error) }

        Services.models?.setUserBusy(true)
        Services.flowBar?.setState(.meeting(.recording(wordCount: 0)))
        if Defaults[.notetakerOpenWindowOnRecord] { Services.hub?.showNotepad(for: meeting.id) }
        let limit = TimeInterval(Defaults[.notetakerMaxRecordingLength])
        session.limitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            guard !Task.isCancelled, let self, self.session === session else { return }
            Log.meetings.info("Maximum recording length reached")
            await self.stop()
        }
        setState(.recording(meetingID: meeting.id))
        Log.meetings.info("Recording meeting \(meeting.id, privacy: .public)")
        return meeting
    }

    /// Nothing could be captured or saved: undo the start and report why.
    private func abandon(_ session: RecordingSession, restoring previous: MeetingRecordingState, error: Error) throws -> Meeting {
        releaseCapture(session)
        self.session = nil
        try? FileManager.default.removeItem(at: session.folder)
        Services.flowBar?.setState(.resting)
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
        guard let channel = session.channels[frame.channel] else { return }
        // Dictated words never enter the meeting (local-models.md §8.3): the mic is muted while a dictation records.
        let muted = frame.channel == .mic && (Services.dictation?.status.isRecording ?? false)
        for utterance in await channel.append(frame.samples, at: frame.time - origin, muted: muted) {
            enqueue(utterance, channel: frame.channel, in: session)
        }
    }

    /// Transcribes utterances of one channel in order, one at a time.
    private func enqueue(_ utterance: Utterance, channel: AudioChannel, in session: RecordingSession) {
        let previous = session.transcription[channel]
        session.transcription[channel] = Task { [weak self] in
            await previous?.value
            guard let self, !session.discarded,
                  let segment = await self.recognize(utterance, channel: channel, vocabulary: session.vocabulary),
                  !session.discarded else { return }
            session.meeting.segments.append(segment)
            session.wordCount += Dictation.countWords(segment.text)
            self.publish(segment)
            if self.session === session, case .recording = self.state {
                Services.flowBar?.setState(.meeting(.recording(wordCount: session.wordCount)))
            }
            self.schedulePersist(session)
            self.scheduleRollingMap(session)
        }
    }

    /// One utterance → one final segment; nil when the engine hears no speech in it (its VAD) or returns nothing.
    private func recognize(_ utterance: Utterance, channel: AudioChannel, vocabulary: [String]) async -> TranscriptSegment? {
        guard let speech = Services.speech else { return nil }
        let clip = AudioClip(samples: utterance.samples, startTime: utterance.start)
        do {
            let transcript = try await speech.transcribe(clip, options: TranscriptionOptions(vocabulary: vocabulary), priority: .meeting)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TranscriptSegment(channel: channel, start: utterance.start, end: utterance.end, text: text)
        } catch SpeechError.noSpeech {
            return nil
        } catch {
            Log.meetings.error("Meeting transcription failed: \(error.localizedDescription, privacy: .public)")
            return nil
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

    /// Appends the user's text to the meeting's notes.
    public func appendNote(_ text: String) {
        guard let id = session?.meeting.id else { return }
        update(id) { row in
            let separator = row.notes.isEmpty || row.notes.hasSuffix("\n") ? "" : "\n"
            row.notes += separator + text
        }
    }

    /// Adds a marker at the current moment of the recording: a "[mm:ss] label" line in the notes.
    public func addMarker(_ label: String) {
        guard let meeting = session?.meeting else { return }
        let stamp = "[\(TranscriptChunker.timestamp(Date().timeIntervalSince(meeting.startedAt)))]"
        appendNote(label.isEmpty ? stamp : stamp + " " + label)
    }

    // MARK: Stop and discard

    public func stop() async {
        guard let session, case .recording(let id) = state else { return }
        setState(.stopping(meetingID: id))
        Services.flowBar?.setState(.meeting(.stopping))
        session.limitTask?.cancel()
        releaseCapture(session)
        for (channel, recorder) in session.channels {
            if let utterance = await recorder.finish() { enqueue(utterance, channel: channel, in: session) }
        }
        session.meeting.endedAt = Date()
        session.persistTask?.cancel()
        persist(session)
        self.session = nil
        Services.models?.setUserBusy(false)
        Services.flowBar?.setState(.resting)
        Log.meetings.info("Stopped meeting \(id, privacy: .public)")
        setState(.processing(meetingID: id, stage: Stage.processingAudio))
        processing[id] = Task { [weak self] in await self?.process(id, folder: session.folder, live: session) }
    }

    public func discard() async {
        if let session {
            session.discarded = true
            session.limitTask?.cancel()
            releaseCapture(session)
            for recorder in session.channels.values { _ = await recorder.finish() }
            for task in session.transcription.values { task.cancel() }
            session.mapTask?.cancel()
            session.persistTask?.cancel()
            self.session = nil
            Services.models?.setUserBusy(false)
            Services.flowBar?.setState(.resting)
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

    private func process(_ id: UUID, folder: URL, live: RecordingSession?) async {
        defer {
            processing[id] = nil
            if session == nil, processing.isEmpty { setState(.idle) }
        }
        stage(id, Stage.processingAudio)
        let system = await Task.detached(priority: .utility) { ChunkedTrackWriter.read(folder: folder, channel: .system) }.value

        stage(id, Stage.transcribing)
        if let live {
            for task in live.transcription.values { await task.value }
            await live.mapTask?.value
            persist(live)
        } else {
            await transcribeTail(of: id, folder: folder)
        }
        guard !Task.isCancelled, Services.meetings.meeting(id) != nil else { return }

        stage(id, Stage.refining)
        var voices: [TranscriptSegment] = []
        if Defaults[.notetakerAttributeNamesEnabled], !system.isEmpty, let speech = Services.speech {
            do { voices = try await speech.diarize(AudioClip(samples: system)) } catch {
                Log.meetings.error("Speaker split failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard !Task.isCancelled else { return }
        update(id) { $0.assignSpeakers(voices: voices) }
        let tracks = await Task.detached(priority: .utility) { () -> [AudioTrack] in
            AudioChannel.allCases.compactMap { channel in
                do { return try MeetingAudioFiles.finalize(folder: folder, channel: channel) } catch {
                    Log.meetings.error("Couldn't write the \(channel.rawValue, privacy: .public) track: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }.value
        guard !Task.isCancelled else { return }
        update(id) { $0.tracks = tracks }

        guard let summarizer = Services.summarizer, summarizer.isModelReady, let meeting = Services.meetings.meeting(id) else { return }
        do {
            stage(id, Stage.summarizing)
            if let summarizer = summarizer as? MeetingSummarizer { try await summarizer.mapChunks(of: meeting) }
            stage(id, Stage.generating)
            let summary = try await summarizer.summarize(Services.meetings.meeting(id) ?? meeting)
            guard !Task.isCancelled else { return }
            update(id) { row in
                row.summary = summary
                if row.calendarEventID == nil, Self.untitledTitles.contains(row.title), !summary.title.isEmpty { row.title = summary.title }
            }
            for item in summary.actionItems { try Services.meetings.save(item) }
        } catch {
            Log.meetings.info("No notes for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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

    /// After a crash: transcribes what was recorded after the last saved segment of each channel.
    private func transcribeTail(of id: UUID, folder: URL) async {
        guard let meeting = Services.meetings.meeting(id) else { return }
        await Self.prepareSpeechEngine()
        let vocabulary = vocabulary(for: meeting)
        var added: [TranscriptSegment] = []
        for channel in AudioChannel.allCases {
            let from = Int((meeting.segments.filter { $0.channel == channel }.map(\.end).max() ?? 0) * Double(AudioClip.sampleRate))
            let samples = await Task.detached(priority: .utility) { ChunkedTrackWriter.read(folder: folder, channel: channel, fromSample: from) }.value
            var segmenter = SpeechSegmenter(startSample: from)
            let utterances = segmenter.append(samples) + [segmenter.flush()].compactMap { $0 }
            for utterance in utterances {
                if let segment = await recognize(utterance, channel: channel, vocabulary: vocabulary) { added.append(segment) }
            }
        }
        if !added.isEmpty { update(id) { $0.segments = ($0.segments + added).sorted { $0.start < $1.start } } }
    }

    /// Finishes meetings a crash or quit interrupted: their chunk files are still in `Audio/Meetings/<id>/`. Each gets an end
    /// time, the transcript of its untranscribed tail, speakers, final audio files and notes, like a normal stop.
    public func recoverInterruptedMeetings() {
        let root = SuperFlowPaths.meetingAudio
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent), id != session?.meeting.id, processing[id] == nil else { continue }
            let chunks = AudioChannel.allCases.flatMap { ChunkedTrackWriter.chunks(in: folder, channel: $0) }
            guard !chunks.isEmpty else { continue }
            guard var meeting = Services.meetings.meeting(id) else {
                try? FileManager.default.removeItem(at: folder)
                continue
            }
            if meeting.endedAt == nil {
                let seconds = AudioChannel.allCases.map { channel in
                    ChunkedTrackWriter.chunks(in: folder, channel: channel).reduce(0) { $0 + ChunkedTrackWriter.sampleCount(of: $1) }
                }.max() ?? 0
                meeting.endedAt = meeting.startedAt.addingTimeInterval(Double(seconds) / Double(AudioClip.sampleRate))
                try? Services.meetings.save(meeting)
            }
            Log.meetings.info("Recovering interrupted meeting \(id, privacy: .public)")
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
    var frameTask: Task<Void, Never>?
    var limitTask: Task<Void, Never>?
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
    /// tracks stay on the meeting's timeline; returns the utterances that closed.
    func append(_ samples: [Float], at offset: TimeInterval, muted: Bool) -> [Utterance] {
        guard !finished else { return [] }
        var block = muted ? [Float](repeating: 0, count: samples.count) : samples
        let gap = Int(offset * Double(AudioClip.sampleRate)) - writer.totalSamples
        if gap > AudioClip.sampleRate / 10, gap < 3 * 3600 * AudioClip.sampleRate {
            block = [Float](repeating: 0, count: gap) + block
        }
        do { try writer.append(block) } catch {
            if !reportedWriteError { Log.meetings.error("Couldn't write meeting audio: \(error.localizedDescription, privacy: .public)") }
            reportedWriteError = true
        }
        return segmenter.append(block)
    }

    func finish() -> Utterance? {
        guard !finished else { return nil }
        finished = true
        writer.close()
        return segmenter.flush()
    }
}

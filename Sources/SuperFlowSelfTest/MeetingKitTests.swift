import AppKit
import Combine
import Foundation
import CleanupKit
import FlowStore
import llama
import MeetingKit
import SuperFlowCore

// Owned with MeetingKit: detection, dual-track recording, speakers, notes, export and retention, run against fake
// engines and a synthetic two-track meeting. The notes smoke test runs the real Qwen3.5-4B only when a folder in
// `SUPERFLOW_DEV_MODELS` (colon-separated) holds its GGUF.
func registerMeetingKitTests() {
    SelfTest.cases.append(("MeetingKit.segmenter", { MainActor.assumeIsolated { meetingSegmenter() } }))
    SelfTest.cases.append(("MeetingKit.chunkedAudio", { MainActor.assumeIsolated { meetingChunkedAudio() } }))
    SelfTest.cases.append(("MeetingKit.detector", { MainActor.assumeIsolated { meetingDetector() } }))
    SelfTest.cases.append(("MeetingKit.promptCoordinator", { MainActor.assumeIsolated { meetingPromptCoordinator() } }))
    SelfTest.cases.append(("MeetingKit.recordEndToEnd", { MainActor.assumeIsolated { meetingRecordEndToEnd() } }))
    SelfTest.cases.append(("MeetingKit.startFailuresAndDiscard", { MainActor.assumeIsolated { meetingStartFailuresAndDiscard() } }))
    SelfTest.cases.append(("MeetingKit.crashRecovery", { MainActor.assumeIsolated { meetingCrashRecovery() } }))
    SelfTest.cases.append(("MeetingKit.killedMidRecording", { MainActor.assumeIsolated { meetingKilledMidRecording() } }))
    SelfTest.cases.append(("MeetingKit.interruptedFinalize", { MainActor.assumeIsolated { meetingInterruptedFinalize() } }))
    SelfTest.cases.append(("MeetingKit.systemAudioDenied", { MainActor.assumeIsolated { meetingSystemAudioDenied() } }))
    SelfTest.cases.append(("MeetingKit.diskFull", { MainActor.assumeIsolated { meetingDiskFull() } }))
    SelfTest.cases.append(("MeetingKit.micLostAndSleep", { MainActor.assumeIsolated { meetingMicLostAndSleep() } }))
    SelfTest.cases.append(("MeetingKit.retryTranscriptAndNotes", { MainActor.assumeIsolated { meetingRetries() } }))
    SelfTest.cases.append(("MeetingKit.speakers", { MainActor.assumeIsolated { meetingSpeakers() } }))
    SelfTest.cases.append(("MeetingKit.summarizer", { MainActor.assumeIsolated { meetingSummarizer() } }))
    SelfTest.cases.append(("MeetingKit.export", { MainActor.assumeIsolated { meetingExport() } }))
    SelfTest.cases.append(("MeetingKit.audioRetention", { MainActor.assumeIsolated { meetingAudioRetention() } }))
    SelfTest.cases.append(("MeetingKit.notesRealModel", { MainActor.assumeIsolated { meetingNotesRealModel() } }))
}

// MARK: - Synthetic meeting

/// Five utterances as pure tones: the mic ("You") at 200/260 Hz, two remote voices on the system track at 400/460 Hz
/// (voice A) and 700 Hz (voice B). The fake engine "hears" a phrase by its frequency.
private enum MeetingFixture {
    static let utterances: [(channel: AudioChannel, start: TimeInterval, duration: TimeInterval, frequency: Double, text: String)] = [
        (.mic, 0.5, 2, 200, "Let's ship the beta on Friday."),
        (.system, 3.0, 2, 400, "Priya will send the pricing proposal by Friday."),
        (.system, 5.6, 2, 700, "I can review the onboarding metrics tomorrow."),
        (.mic, 8.2, 2, 260, "Great, so we agreed to ship the beta on Friday."),
        (.system, 10.8, 2, 460, "What about the Android release?"),
    ]
    static let length: TimeInterval = 14
    static let rate = Double(AudioClip.sampleRate)

    static func track(_ channel: AudioChannel) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(length * rate))
        for u in utterances where u.channel == channel {
            for i in Int(u.start * rate)..<Int((u.start + u.duration) * rate) {
                samples[i] = 0.3 * Float(sin(2 * Double.pi * u.frequency * Double(i) / rate))
            }
        }
        return samples
    }

    /// Interleaved 40 ms frames of both channels on a host clock starting at `base`.
    static func frames(base: TimeInterval, from: TimeInterval = 0, to: TimeInterval = length) -> [AudioFrame] {
        let mic = track(.mic), system = track(.system)
        var frames: [AudioFrame] = []
        var i = Int(from * rate)
        while i + 640 <= Int(to * rate) {
            let time = base + Double(i) / rate
            frames.append(AudioFrame(channel: .mic, samples: Array(mic[i..<i + 640]), time: time, level: 0))
            frames.append(AudioFrame(channel: .system, samples: Array(system[i..<i + 640]), time: time, level: 0))
            i += 640
        }
        return frames
    }

    static var words: Int { utterances.reduce(0) { $0 + Dictation.countWords($1.text) } }
}

/// Frequency of a tone from its zero crossings over the voiced part.
private func meetingFrequency(_ samples: [Float]) -> Double {
    guard let first = samples.firstIndex(where: { abs($0) > 0.05 }), let last = samples.lastIndex(where: { abs($0) > 0.05 }), last > first else { return 0 }
    var crossings = 0
    var previous: Float = 0
    for sample in samples[first...last] where sample != 0 {
        if previous != 0, (sample > 0) != (previous > 0) { crossings += 1 }
        previous = sample
    }
    return Double(crossings) / 2 / (Double(last - first) / Double(AudioClip.sampleRate))
}

private func meetingRMS(_ samples: ArraySlice<Float>) -> Float {
    samples.isEmpty ? 0 : (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
}

// MARK: - Fakes

@MainActor private final class MeetingFakeAudio: AudioCapturing {
    var devices: [AudioDevice] = []
    var selectedDevice: AudioDevice? { nil }
    var micHolders = 0
    var isCapturingMicrophone: Bool { micHolders > 0 }
    var isCapturingSystemAudio = false
    var systemAudioMethod: SystemAudioMethod { .processTap }
    var micError: Error?
    var systemError: Error?
    private var subscribers: [UUID: AsyncStream<AudioFrame>.Continuation] = [:]

    var subscriberCount: Int { subscribers.count }
    var frames: AsyncStream<AudioFrame> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[id] = continuation
            continuation.onTermination = { _ in Task { @MainActor in self.subscribers[id] = nil } }
        }
    }
    var level: AnyPublisher<Float, Never> { Just(0).eraseToAnyPublisher() }
    var deviceChanges: AnyPublisher<[AudioDevice], Never> { Just(devices).eraseToAnyPublisher() }

    var micStarts = 0
    func startMicrophone() async throws {
        if let micError { throw micError }
        micHolders += 1
        micStarts += 1
    }
    func stopMicrophone() { micHolders = max(0, micHolders - 1) }
    func startSystemAudio() async throws {
        if let systemError { throw systemError }
        isCapturingSystemAudio = true
    }
    func stopSystemAudio() { isCapturingSystemAudio = false }
    func muteOutput() {}
    func unmuteOutput() {}
    func play(_ cue: SoundCue) {}

    func feed(_ frames: [AudioFrame]) {
        for frame in frames { for continuation in subscribers.values { continuation.yield(frame) } }
    }
}

@MainActor private final class MeetingFakeSpeech: SpeechRecognizing {
    var availableEngines: [String] { ["fake"] }
    var activeEngineID: String? { "fake" }
    var diarizeError: Error?
    var priorities: [SpeechPriority] = []

    func prepare(modelID: String) async throws {}
    func unload() {}

    /// Set to make every transcription fail (the engine isn't ready).
    var transcribeError: Error?

    func transcribe(_ audio: AudioClip, options: TranscriptionOptions, priority: SpeechPriority) async throws -> Transcript {
        priorities.append(priority)
        if let transcribeError { throw transcribeError }
        let frequency = meetingFrequency(audio.samples)
        guard let match = MeetingFixture.utterances.min(by: { abs($0.frequency - frequency) < abs($1.frequency - frequency) }),
              abs(match.frequency - frequency) < 25 else { throw SpeechError.noSpeech }
        return Transcript(text: match.text)
    }

    func transcribeIncrementally(_ audio: AsyncStream<AudioClip>, options: TranscriptionOptions, priority: SpeechPriority)
        -> AsyncThrowingStream<TranscriptionEvent, Error> { AsyncThrowingStream { $0.finish() } }

    func speechSegments(in audio: AudioClip) async -> [Range<Int>] {
        meetingRMS(audio.samples[...]) > 0.01 ? [0..<audio.samples.count] : []
    }

    /// Voiced 100 ms windows below 550 Hz are voice A, above it voice B; runs of one voice become turns.
    let voiceA = UUID(), voiceB = UUID()
    func diarize(_ audio: AudioClip) async throws -> [TranscriptSegment] {
        if let diarizeError { throw diarizeError }
        var turns: [TranscriptSegment] = []
        let window = 1600
        var start = 0
        while start + window <= audio.samples.count {
            let slice = Array(audio.samples[start..<start + window])
            if meetingRMS(slice[...]) > 0.02 {
                let voice = meetingFrequency(slice) < 550 ? voiceA : voiceB
                let time = Double(start) / Double(AudioClip.sampleRate)
                if let last = turns.last, last.speakerID == voice, abs(last.end - time) < 0.01 { turns[turns.count - 1].end = time + 0.1 }
                else { turns.append(TranscriptSegment(channel: .system, speakerID: voice, start: time, end: time + 0.1, text: "")) }
            }
            start += window
        }
        return turns
    }
}

@MainActor private final class MeetingFakeStore: MeetingStoring {
    var rows: [UUID: Meeting] = [:]
    var items: [UUID: ActionItem] = [:]
    let subject = PassthroughSubject<StoreChange, Never>()
    var changes: AnyPublisher<StoreChange, Never> { subject.eraseToAnyPublisher() }

    func meeting(_ id: UUID) -> Meeting? { rows[id] }
    func meetings(matching query: String, limit: Int, offset: Int) -> [Meeting] { rows.values.sorted { $0.startedAt > $1.startedAt } }
    func save(_ meeting: Meeting) throws { rows[meeting.id] = meeting; subject.send(.meetings) }
    func deleteMeeting(_ id: UUID) throws {
        guard rows.removeValue(forKey: id) != nil else { throw StoreError.notFound(id) }
        try? FileManager.default.removeItem(at: SuperFlowPaths.meetingAudio.appendingPathComponent(id.uuidString))
        subject.send(.meetings)
    }
    func meetingsWithAudio(before cutoff: Date) -> [Meeting] {
        rows.values.filter { $0.hasAudio && ($0.endedAt ?? .distantFuture) < cutoff }
    }
    func pruneMeetings(before cutoff: Date) throws -> Int { 0 }
    var actionItems: [ActionItem] { items.values.sorted { $0.sortOrder < $1.sortOrder } }
    func save(_ item: ActionItem) throws { items[item.id] = item }
    func deleteActionItem(_ id: UUID) throws { items[id] = nil }
}

@MainActor private final class MeetingFakeFlowBar: FlowBarPresenting {
    var state: FlowBarState = .resting
    var states: [FlowBarState] = []
    var phases: [MeetingBarPhase?] = []
    var prompts: [MeetingPrompt] = []
    var answer: ((MeetingPromptAnswer) -> Void)?

    func setState(_ state: FlowBarState) { self.state = state; states.append(state) }
    func setMeetingPhase(_ phase: MeetingBarPhase?) {
        phases.append(phase)
        state = phase.map { .meeting($0) } ?? .resting
    }
    func setLevel(_ level: Float) {}
    func setEdge(_ edge: FlowBarEdge) {}
    func setRestingVisible(_ visible: Bool) {}
    var notifications: [FlowBarNotification] = []
    func show(_ notification: FlowBarNotification, onAction: @escaping (String) -> Void) { notifications.append(notification) }
    func dismiss(notificationID: String) {}
    func showMeetingPrompt(_ prompt: MeetingPrompt, onAnswer: @escaping (MeetingPromptAnswer) -> Void) {
        prompts.append(prompt)
        answer = onAnswer
    }
    func showLiveText(_ text: String?) {}
}

@MainActor private final class MeetingFakeHub: HubPresenting {
    var notepads: [UUID] = []
    func show(_ page: HubPage) {}
    func showSettings(_ pane: SettingsPane) {}
    func showMeeting(_ id: UUID) {}
    func showNotepad(for meetingID: UUID) { notepads.append(meetingID) }
    var isVisible: Bool { false }
}

/// Canned LLM answers by request kind; `extract` sees the chunk text, so it can answer from what is in it.
@MainActor private final class MeetingFakeNotesModel: NotesLanguageModel {
    var modelID = "fake-notes"
    var isReady = true
    var inputWordBudget = 1000
    var calls: [NotesRequest.Kind] = []
    var inputs: [String] = []
    var extract: (String) -> String = { _ in "{}" }
    var condense: (String) -> String = { _ in "{}" }
    var write = "{}"
    var answer: (String) -> String = { $0 }

    func complete(_ request: NotesRequest) async throws -> String {
        calls.append(request.kind)
        inputs.append(request.input)
        switch request.kind {
        case .extract: return extract(request.input)
        case .condense: return condense(request.input)
        case .write: return write
        case .answer: return answer(request.input)
        }
    }
}

/// Swaps the fakes into `Services` for one test and puts the previous services back.
@MainActor private final class MeetingFakes {
    let audio = MeetingFakeAudio(), speech = MeetingFakeSpeech(), store = MeetingFakeStore(), flowBar = MeetingFakeFlowBar(), hub = MeetingFakeHub()
    let notes = MeetingFakeNotesModel()
    private let saved: (AudioCapturing?, SpeechRecognizing?, MeetingStoring?, FlowBarPresenting?, HubPresenting?, MeetingSummarizing?)

    init() {
        saved = (Services.audio, Services.speech, Services.meetings, Services.flowBar, Services.hub, Services.summarizer)
        Services.audio = audio
        Services.speech = speech
        Services.meetings = store
        Services.flowBar = flowBar
        Services.hub = hub
        Services.summarizer = MeetingSummarizer(model: notes)
        notes.extract = meetingFixtureNotes
        notes.write = #"{"title": "Beta ship date", "summary": "The team will ship the beta on Friday. Priya sends the pricing proposal. The company raised 20 million dollars."}"#
    }

    func restore() {
        Services.audio = saved.0
        Services.speech = saved.1
        Services.meetings = saved.2
        Services.flowBar = saved.3
        Services.hub = saved.4
        Services.summarizer = saved.5
    }
}

/// What a model might say about the fixture, including things the transcript never said (a budget, a venue, "Bob").
private func meetingFixtureNotes(_ input: String) -> String {
    guard input.contains("pricing proposal") else { return #"{"key_points": ["Ask about Android."]}"# }
    return """
        <think>Let me list the notes.</think>
        ```json
        {"key_points": ["The beta ships on Friday.", "Android release timing is open."],
         "decisions": ["Ship the beta on Friday.", "Budget approved at 5000 dollars."],
         "action_items": [{"task": "Send the pricing proposal", "owner": "Priya", "due": "by Friday"},
                          {"task": "Review the onboarding metrics", "owner": "Speaker 2", "due": "tomorrow"},
                          {"task": "Book the venue", "owner": "Bob", "due": null},],
         "open_questions": ["What about the Android release?"],}
        ```
        """
}

@MainActor private final class MeetingBox<T> {
    var items: [T] = []
    private var task: Task<Void, Never>?
    init() {}
    init(_ stream: AsyncStream<T>) {
        task = Task { @MainActor [weak self] in for await item in stream { self?.items.append(item) } }
    }
    func cancel() { task?.cancel() }
}

@MainActor @discardableResult private func meetingWaitUntil(_ seconds: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}

@MainActor private func meetingPump(_ seconds: TimeInterval = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

private func meetingTemporaryFolder() -> URL {
    SuperFlowPaths.ensure(SuperFlowPaths.support.appendingPathComponent("meetingkit-\(UUID().uuidString)", isDirectory: true))
}

// MARK: - Audio

@MainActor private func meetingSegmenter() {
    var segmenter = SpeechSegmenter()
    let mic = MeetingFixture.track(.mic)
    var utterances: [Utterance] = []
    for start in stride(from: 0, to: mic.count, by: 640) { utterances += segmenter.append(Array(mic[start..<min(start + 640, mic.count)])) }
    if let tail = segmenter.flush() { utterances.append(tail) }
    check(utterances.count == 2, "two mic utterances, got \(utterances.count)")
    if utterances.count == 2 {
        check(abs(utterances[0].start - 0.3) < 0.03 && utterances[0].end > 2.5 && utterances[0].end < 2.75,
              "first utterance keeps 200 ms of onset and a short tail: \(utterances[0].start)–\(utterances[0].end)")
        check(abs(utterances[1].start - 8.0) < 0.03, "second utterance on the recording's timeline: \(utterances[1].start)")
    }

    var long = SpeechSegmenter(startSample: 16_000)
    let tone = (0..<(20 * 16_000)).map { 0.3 * Float(sin(2 * Double.pi * 300 * Double($0) / 16_000)) }
    var pieces = long.append(tone)
    if let tail = long.flush() { pieces.append(tail) }
    check(pieces.count == 2 && abs(pieces[0].end - pieces[0].start - SpeechSegmenter.maxLength) < 0.03 && abs(pieces[0].start - 1) < 0.001,
          "a 20 s monologue closes at 15 s and is offset by startSample")

    var clicks = SpeechSegmenter()
    let click = [Float](repeating: 0, count: 8000) + (0..<1600).map { _ in Float(0.5) } + [Float](repeating: 0, count: 16_000)
    check(clicks.append(click).isEmpty && clicks.flush() == nil, "a 100 ms click is not speech")
}

@MainActor private func meetingChunkedAudio() {
    let folder = meetingTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let ramp = (0..<(70 * 16_000)).map { Float(sin(Double($0) / 50)) * 0.5 }
    let writer = ChunkedTrackWriter(folder: folder, channel: .mic)
    for start in stride(from: 0, to: ramp.count, by: 640) { try? writer.append(Array(ramp[start..<min(start + 640, ramp.count)])) }
    writer.close()
    check(ChunkedTrackWriter.chunks(in: folder, channel: .mic).count == 3, "70 s → three 30 s chunks")
    let back = ChunkedTrackWriter.read(folder: folder, channel: .mic)
    check(back.count == ramp.count && zip(back, ramp).allSatisfy { abs($0 - $1) < 1e-4 }, "chunks read back as written (16-bit)")
    let tail = ChunkedTrackWriter.read(folder: folder, channel: .mic, fromSample: 40 * 16_000)
    check(tail.count == 30 * 16_000 && abs(tail[0] - ramp[40 * 16_000]) < 1e-4, "reading from an offset skips whole and partial chunks")

    // A writer that is never closed (a crash) loses nothing it appended; a new one continues the numbering.
    let crashed = ChunkedTrackWriter(folder: folder, channel: .mic)
    check(crashed.totalSamples == ramp.count, "a reopened writer continues after the existing chunks")
    try? crashed.append([Float](repeating: 0.25, count: 16_000))
    check(ChunkedTrackWriter.read(folder: folder, channel: .mic).count == 71 * 16_000, "unclosed chunk is readable")

    switch Result(catching: { try MeetingAudioFiles.finalize(folder: folder, channel: .mic) }) {
    case .success(let track?):
        let url = folder.appendingPathComponent(track.file)
        check(track.file == "mic.m4a" && abs(track.duration - 71) < 0.01 && track.byteSize > 0 && track.byteSize < 71 * 16_000,
              "final AAC track: \(track.duration) s, \(track.byteSize) bytes")
        check(ChunkedTrackWriter.chunks(in: folder, channel: .mic).isEmpty, "chunks deleted after encoding")
        let decoded = (try? AudioClip.samples(of: url)) ?? []
        check(abs(decoded.count - 71 * 16_000) <= 2048, "AAC decodes to 71 s at 16 kHz (\(decoded.count) samples)")
        check((try? MeetingAudioFiles.finalize(folder: folder, channel: .mic))??.file == "mic.m4a", "finalizing again keeps the track")
    default: check(false, "finalize produced a track")
    }
    check((try? MeetingAudioFiles.finalize(folder: folder, channel: .system)) == .some(nil), "a channel without audio has no track")
}

// MARK: - Detection

@MainActor private final class MeetingFakeEnvironment: MeetingEnvironment {
    var holders: [MicrophoneHolder] = []
    var running: Set<String> = []
    var titles: [String: [String]] = [:]
    var events: [CalendarEvent] = []
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    func microphoneHolders() -> [MicrophoneHolder] { holders }
    func isRunning(_ bundleID: String) -> Bool { running.contains(bundleID) }
    func windowTitles(of bundleID: String) -> [String] { titles[bundleID] ?? [] }
    func calendarEvents(from: Date, to: Date) -> [CalendarEvent] { events.filter { $0.end > from && $0.start < to } }
    func now() -> Date { clock }
}

@MainActor private func meetingDetector() {
    let env = MeetingFakeEnvironment()
    let detector = MeetingDetector(environment: env)
    let signals = MeetingBox(detector.signals)
    defer { signals.cancel() }
    func step(_ seconds: TimeInterval) { env.clock += seconds; detector.poll(); meetingPump(0.02) }
    func started() -> [DetectedMeeting] { signals.items.compactMap { if case .started(let m) = $0 { return m }; return nil } }
    func ended() -> [(String, Bool)] { signals.items.compactMap { if case .ended(let id, let c) = $0 { return (id, c) }; return nil } }

    // Zoom with a calendar event now → a meeting after the start delay, titled from the calendar.
    let standup = CalendarEvent(id: "evt-zoom", title: "Weekly product sync", start: env.clock.addingTimeInterval(-120),
                                end: env.clock.addingTimeInterval(1800), attendees: [Participant(name: "Priya")],
                                joinURL: URL(string: "https://us02web.zoom.us/j/123"), platform: .zoom)
    env.events = [standup]
    env.holders = [MicrophoneHolder(pid: 10, bundleID: "us.zoom.xos")]
    step(0); step(2)
    check(started().isEmpty, "a mic held under 3 s is not a meeting yet")
    step(1.5)
    check(started().count == 1 && started().first?.platform == .zoom && started().first?.title == "Weekly product sync"
          && started().first?.calendarEvent?.id == "evt-zoom" && started().first?.bundleID == "us.zoom.xos", "Zoom meeting with its calendar title")
    check(detector.activeMeetings.count == 1, "one active meeting")

    // Released, back inside the grace period: still the same meeting; released for good: a confident end.
    env.holders = []
    step(2); step(10)
    env.holders = [MicrophoneHolder(pid: 10, bundleID: "us.zoom.xos")]
    step(2)
    check(started().count == 1 && ended().isEmpty, "returning within the grace period cancels the end")
    env.holders = []
    step(1); step(16)
    check(ended().count == 1 && ended().first?.0 == started().first?.id && ended().first?.1 == true, "native app releasing the mic ends confidently")
    check(detector.activeMeetings.isEmpty, "no active meeting after the end")

    // Browser: Chrome's helper holds the mic on a Meet tab; a non-meeting page with the mic is not a meeting.
    env.events = []
    env.holders = [MicrophoneHolder(pid: 20, bundleID: "com.google.Chrome.helper")]
    env.titles["com.google.Chrome"] = ["YouTube - Google Chrome"]
    step(0); step(4)
    check(started().count == 1, "a browser with the mic but no meeting page is ignored")
    env.titles["com.google.Chrome"] = ["Inbox", "Meet - abc-defg-hij - Google Chrome"]
    step(0); step(4)
    check(started().last?.platform == .googleMeet && started().last?.bundleID == "com.google.Chrome" && started().last?.title == "Untitled meeting",
          "Meet in Chrome via its helper process")
    env.holders = []
    step(1); step(16)
    check(ended().last?.1 == false, "mic released while the Meet page is still open is a low-confidence end")

    // FaceTime captures through avconferenced; Safari through WebKit's processes; Slack huddles through Slack's helper.
    env.holders = [MicrophoneHolder(pid: 30, bundleID: "com.apple.avconferenced"),
                   MicrophoneHolder(pid: 31, bundleID: "com.apple.WebKit.GPU"),
                   MicrophoneHolder(pid: 32, bundleID: "com.tinyspeck.slackmacgap.helper")]
    env.running = ["com.apple.Safari"]
    env.titles["com.apple.Safari"] = ["Microsoft Teams meeting | Microsoft Teams"]
    step(0); step(4)
    let platforms = Set(started().suffix(3).map(\.platform))
    check(platforms == [.facetime, .teams, .slack], "FaceTime, Teams in Safari and a Slack huddle: \(platforms)")
    env.holders = []
    step(1); step(16)

    // Calendar reminder once, inside the lead time (default 1 minute).
    env.events = [CalendarEvent(id: "evt-next", title: "Design review", start: env.clock.addingTimeInterval(50),
                                end: env.clock.addingTimeInterval(3600), joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                                platform: .googleMeet),
                  CalendarEvent(id: "evt-solo", title: "Focus time", start: env.clock.addingTimeInterval(40), end: env.clock.addingTimeInterval(600))]
    step(1); step(2)
    let reminders = signals.items.compactMap { if case .calendarReminder(let e, let s) = $0 { return (e.id, s) }; return nil }
    check(reminders.count == 1 && reminders.first?.0 == "evt-next" && (reminders.first?.1 ?? 0) > 0 && (reminders.first?.1 ?? 99) <= 60,
          "one reminder for the meeting-like event, none for focus time")
    let upcoming = complete { await detector.upcomingEvents(within: 3600) }
    if case .success(let events)? = upcoming { check(events.map(\.id) == ["evt-next"], "upcoming meetings only") } else { check(false, "upcoming events") }
    check(CalendarEvent(id: "x", title: "", start: Date(), end: Date()).joinURL == nil, "sanity")
}

@MainActor private final class MeetingFakeDetector: MeetingDetecting {
    var isRunning: Bool { true }
    func start() {}
    func stop() {}
    var activeMeetings: [DetectedMeeting] { [] }
    private var continuations: [AsyncStream<MeetingSignal>.Continuation] = []
    var signals: AsyncStream<MeetingSignal> { AsyncStream { continuations.append($0) } }
    func upcomingEvents(within: TimeInterval) async -> [CalendarEvent] { [] }
    func send(_ signal: MeetingSignal) { for continuation in continuations { continuation.yield(signal) }; meetingPump(0.05) }
}

@MainActor private func meetingPromptCoordinator() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let detector = MeetingFakeDetector()
    let recorder = MeetingRecorder()
    let coordinator = MeetingPromptCoordinator(detector: detector, recorder: recorder)
    coordinator.start()
    defer { coordinator.stop() }

    let zoom = DetectedMeeting(id: "us.zoom.xos#1", platform: .zoom, title: "Untitled meeting", bundleID: "us.zoom.xos")
    detector.send(.started(zoom))
    check(fakes.flowBar.prompts.count == 1 && fakes.flowBar.prompts.first?.platform == .zoom, "a detected meeting asks")
    fakes.flowBar.answer?(.notThisOne)
    meetingPump()
    check(recorder.state == .idle, "\"Not this one\" never records")
    detector.send(.started(zoom))
    check(fakes.flowBar.prompts.count == 1, "the same meeting is not asked about twice")

    coordinator.setNeverAsk(true, bundleID: "com.hnc.Discord")
    detector.send(.started(DetectedMeeting(id: "discord#1", platform: .discord, title: "Untitled meeting", bundleID: "com.hnc.Discord")))
    check(fakes.flowBar.prompts.count == 1 && coordinator.neverAskApps == ["com.hnc.Discord"], "apps on the don't-ask list are not asked about")
    coordinator.setNeverAsk(false, bundleID: "com.hnc.Discord")

    Defaults[.meetingDetection] = .doNothing
    detector.send(.started(DetectedMeeting(id: "teams#1", platform: .teams, title: "Untitled meeting", bundleID: "com.microsoft.teams2")))
    check(fakes.flowBar.prompts.count == 1, "\"Do nothing\" never asks")
    Defaults.reset(.meetingDetection)

    // Ending clears the "asked" mark; a new call of the same app asks again; "Record" records it; the call ending stops it.
    detector.send(.ended(id: zoom.id, confident: true))
    let second = DetectedMeeting(id: "us.zoom.xos#2", platform: .zoom, title: "Untitled meeting", bundleID: "us.zoom.xos")
    detector.send(.started(second))
    check(fakes.flowBar.prompts.count == 2, "a new meeting asks again")
    fakes.flowBar.answer?(.record)
    meetingWaitUntil(5) { if case .recording = recorder.state { return true }; return false }
    check(recorder.detectedMeetingID == second.id, "a click on Record starts the recording for that meeting")
    detector.send(.started(DetectedMeeting(id: "slack#1", platform: .slack, title: "Untitled meeting", bundleID: "com.tinyspeck.slackmacgap")))
    check(fakes.flowBar.prompts.count == 2, "no prompt while recording")
    detector.send(.ended(id: second.id, confident: false))
    check(recorder.detectedMeetingID == second.id, "a low-confidence end keeps recording")
    detector.send(.ended(id: second.id, confident: true))
    meetingWaitUntil(5) { recorder.detectedMeetingID == nil }
    check(recorder.detectedMeetingID == nil, "the call ending stops the Notetaker (auto-end on)")
    _ = complete(30) { await recorder.waitForProcessing() }

    // A calendar reminder asks once; the detected meeting for that event is not asked about again.
    let event = CalendarEvent(id: "evt-1", title: "Design review", start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(3600),
                              joinURL: URL(string: "https://meet.google.com/abc"), platform: .googleMeet)
    detector.send(.calendarReminder(event, startsIn: 60))
    check(fakes.flowBar.prompts.count == 3 && fakes.flowBar.prompts.last?.calendarEvent?.id == "evt-1", "calendar reminder prompt")
    fakes.flowBar.answer?(.dismissed)
    detector.send(.started(DetectedMeeting(id: "chrome#9", platform: .googleMeet, title: "Design review", bundleID: "com.google.Chrome",
                                           calendarEvent: event)))
    check(fakes.flowBar.prompts.count == 3, "the reminder already asked about this event")
    check(recorder.state == .idle, "nothing recorded without a click")
}

// MARK: - Recording

@MainActor private func meetingRecordEndToEnd() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let recorder = MeetingRecorder()
    recorder.persistInterval = 0.05
    let live = MeetingBox(recorder.liveSegments)
    let states = MeetingBox<MeetingRecordingState>()
    let subscription = recorder.stateChanges.sink { states.items.append($0) }
    defer { subscription.cancel(); live.cancel() }

    guard case .success(let meeting)? = complete(10, { try await recorder.start(nil) }) else { check(false, "recording starts"); return }
    check(meeting.title == "Untitled note" && recorder.state == .recording(meetingID: meeting.id), "manual note is recording")
    check(fakes.audio.micHolders == 1 && fakes.audio.isCapturingSystemAudio && fakes.audio.subscriberCount == 1, "mic and system audio captured")
    check(fakes.hub.notepads == [meeting.id], "Notepad opened (notetakerOpenWindowOnRecord)")
    check(fakes.store.rows[meeting.id] != nil, "row saved at start")

    // The Notepad edits the notes through the store while the recorder keeps saving the transcript.
    var edited = fakes.store.rows[meeting.id]!
    edited.notes = "Ask about Android."
    try? fakes.store.save(edited)

    fakes.audio.feed(MeetingFixture.frames(base: 5_000))
    meetingWaitUntil { live.items.count >= 5 }
    recorder.addMarker("Pricing")
    let folder = SuperFlowPaths.meetingAudio.appendingPathComponent(meeting.id.uuidString)
    check(!ChunkedTrackWriter.chunks(in: folder, channel: .mic).isEmpty && !ChunkedTrackWriter.chunks(in: folder, channel: .system).isEmpty,
          "both tracks are on disk while recording")
    check(live.items.map(\.text) == MeetingFixture.utterances.map(\.text) && live.items.map(\.channel) == MeetingFixture.utterances.map(\.channel),
          "live transcript in order with You/Them channels: \(live.items.map(\.text))")
    if let first = live.items.first { check(abs(first.start - 0.3) < 0.05, "timestamps relative to the recording start (\(first.start))") }
    check(fakes.speech.priorities.allSatisfy { $0 == .meeting }, "meeting transcription runs at meeting priority")
    check(fakes.flowBar.phases.contains(.recording(wordCount: MeetingFixture.words, startedAt: meeting.startedAt)), "the bar shows the live word count")
    meetingWaitUntil(2) { fakes.store.rows[meeting.id]?.segments.count == 5 }
    check(fakes.store.rows[meeting.id]?.segments.count == 5, "transcript saved while recording")

    _ = complete(10) { await recorder.stop() }
    check(fakes.audio.micHolders == 0 && !fakes.audio.isCapturingSystemAudio, "captures released")
    check(fakes.flowBar.state == .resting, "the bar rests after stopping")
    _ = complete(60) { await recorder.waitForProcessing() }
    meetingWaitUntil(2) { fakes.audio.subscriberCount == 0 }
    check(fakes.audio.subscriberCount == 0, "frame subscription ended")
    check(recorder.state == .idle, "idle after processing")
    let stages = states.items.compactMap { if case .processing(_, let stage) = $0 { return stage }; return nil }
    check(stages == [MeetingRecorder.Stage.processingAudio, MeetingRecorder.Stage.transcribing, MeetingRecorder.Stage.refining,
                     MeetingRecorder.Stage.summarizing, MeetingRecorder.Stage.generating], "processing stages in order: \(stages)")

    guard let saved = fakes.store.rows[meeting.id] else { check(false, "meeting kept"); return }
    check(saved.endedAt != nil && saved.segments.count == 5, "ended with the full transcript")
    check(saved.notes == "Ask about Android." && saved.markers.map(\.label) == ["Pricing"] && (saved.markers.first?.time ?? -1) >= 0,
          "notes kept, marker added: \(saved.markers)")
    check(saved.speakers.map(\.label) == ["You", "Speaker 1", "Speaker 2"], "You + two diarized voices: \(saved.speakers.map(\.label))")
    let labels = speakerLines(saved)
    check(labels == ["You", "Speaker 1", "Speaker 2", "You", "Speaker 1"], "segments labelled by voice: \(labels)")
    check(saved.tracks.map(\.channel) == [.mic, .system] && saved.tracks.allSatisfy { abs($0.duration - MeetingFixture.length) < 0.5 },
          "two final tracks of the meeting's length: \(saved.tracks.map(\.duration))")
    check(saved.tracks.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.file).path) }, "track files exist")
    check(ChunkedTrackWriter.chunks(in: folder, channel: .mic).isEmpty && ChunkedTrackWriter.chunks(in: folder, channel: .system).isEmpty,
          "chunks removed once encoded")

    guard let summary = saved.summary else { check(false, "notes written"); return }
    check(saved.title == "Beta ship date" && summary.title == "Beta ship date", "an untitled note takes the generated title")
    check(summary.summary == "The team will ship the beta on Friday. Priya sends the pricing proposal.", "invented sentence dropped: \(summary.summary)")
    check(summary.decisions == ["Ship the beta on Friday."], "invented decision dropped: \(summary.decisions)")
    check(summary.actionItems.map(\.text) == ["Send the pricing proposal", "Review the onboarding metrics"], "invented task dropped")
    check(summary.actionItems.map(\.owner) == ["Priya", "Speaker 2"], "owners as said")
    let calendar = Calendar.current
    if let due = summary.actionItems.first?.due {
        check(calendar.component(.weekday, from: due) == 6 && due > saved.startedAt && due < saved.startedAt.addingTimeInterval(8 * 86_400),
              "\"by Friday\" → the next Friday")
    } else { check(false, "due date resolved") }
    check(summary.actionItems.last?.due == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: saved.startedAt)), "\"tomorrow\"")
    check(summary.followUps == ["What about the Android release?"] && summary.modelID == "fake-notes", "follow-ups and model id")
    check(fakes.store.actionItems.count == 2 && fakes.store.actionItems.allSatisfy { $0.meetingID == meeting.id }, "action items become tasks")

    // Naming a voice everywhere relabels its blocks and its tasks.
    if let voice = saved.speakers.first(where: { $0.label == "Speaker 2" }) {
        try? recorder.renameSpeaker(voice.id, to: "Sam", inMeeting: meeting.id)
        check(fakes.store.rows[meeting.id]?.speakers.first { $0.id == voice.id }?.displayName == "Sam", "speaker renamed")
        check(fakes.store.actionItems.contains { $0.owner == "Sam" } && fakes.store.rows[meeting.id]?.summary?.actionItems.last?.owner == "Sam",
              "tasks follow the new name")
    }
}

private func speakerLines(_ meeting: Meeting) -> [String] {
    meeting.segments.sorted { $0.start < $1.start }.map { meeting.speakerLabel(for: $0) }
}

@MainActor private func meetingStartFailuresAndDiscard() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let recorder = MeetingRecorder()
    let foldersBefore = (try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.meetingAudio.path).count) ?? 0

    // Nothing can be captured: nothing is saved, and dictation's hold on the mic is untouched.
    fakes.audio.micHolders = 1
    fakes.audio.micError = AudioError.permissionDenied
    fakes.audio.systemError = AudioError.systemAudioUnsupported
    if case .failure(let error)? = complete(10, { try await recorder.start(nil) }) {
        check(error as? AudioError == .permissionDenied, "the microphone error is reported")
    } else { check(false, "start must fail without any audio") }
    check(recorder.state == .idle && fakes.store.rows.isEmpty && fakes.audio.micHolders == 1, "nothing saved, mic count untouched")
    check(((try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.meetingAudio.path).count) ?? 0) == foldersBefore, "no folder left")

    // System audio missing still records "You"; a second start is refused; discard removes everything.
    fakes.audio.micHolders = 0
    fakes.audio.micError = nil
    guard case .success(let meeting)? = complete(10, { try await recorder.start(nil) }) else { check(false, "mic-only recording starts"); return }
    check(!fakes.audio.isCapturingSystemAudio && fakes.audio.micHolders == 1, "mic-only meeting")
    if case .failure(let error)? = complete(10, { try await recorder.start(nil) }) {
        check(error as? MeetingRecorderError == .alreadyRecording, "one recording at a time")
    } else { check(false, "second start refused") }
    fakes.audio.feed(MeetingFixture.frames(base: 100, to: 6))
    meetingWaitUntil(5) { recorder.currentMeeting?.segments.isEmpty == false }
    _ = complete(10) { await recorder.discard() }
    let folder = SuperFlowPaths.meetingAudio.appendingPathComponent(meeting.id.uuidString)
    check(recorder.state == .idle && fakes.store.rows[meeting.id] == nil && !FileManager.default.fileExists(atPath: folder.path),
          "discard deletes the row and its audio")
    check(fakes.audio.micHolders == 0, "discard releases the mic")
}

@MainActor private func meetingCrashRecovery() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let recorder = MeetingRecorder()
    // The app died 14 s into a meeting; only the first mic segment had been saved.
    let started = Date().addingTimeInterval(-600)
    let first = MeetingFixture.utterances[0]
    let meeting = Meeting(title: "Untitled note", startedAt: started,
                          segments: [TranscriptSegment(channel: .mic, start: 0.3, end: 2.7, text: first.text)])
    try? fakes.store.save(meeting)
    let folder = SuperFlowPaths.meetingAudio(meeting.id)
    for channel in AudioChannel.allCases {
        let writer = ChunkedTrackWriter(folder: folder, channel: channel)
        try? writer.append(MeetingFixture.track(channel))
    }
    let orphan = SuperFlowPaths.meetingAudio(UUID())
    try? Data([0, 0]).write(to: orphan.appendingPathComponent("mic-00000.pcm"))
    // A recording whose row is gone (the store was rebuilt from a damaged file): its audio is never thrown away.
    let lostID = UUID()
    let lost = SuperFlowPaths.meetingAudio(lostID)
    for channel in AudioChannel.allCases { try? ChunkedTrackWriter(folder: lost, channel: channel).append(MeetingFixture.track(channel)) }
    // And one that had already been encoded into its final files before its row was lost.
    let encodedID = UUID()
    let encoded = SuperFlowPaths.meetingAudio(encodedID)
    for channel in AudioChannel.allCases {
        try? ChunkedTrackWriter(folder: encoded, channel: channel).append(MeetingFixture.track(channel))
        _ = try? MeetingAudioFiles.finalize(folder: encoded, channel: channel)
    }

    recorder.recoverInterruptedMeetings()
    _ = complete(60) { await recorder.waitForProcessing() }
    guard let saved = fakes.store.rows[meeting.id] else { check(false, "recovered meeting kept"); return }
    check(abs((saved.endedAt?.timeIntervalSince(started) ?? 0) - MeetingFixture.length) < 0.1, "end time from the recorded audio")
    check(saved.segments.map(\.text) == MeetingFixture.utterances.map(\.text), "the untranscribed tail is transcribed: \(saved.segments.map(\.text))")
    check(saved.speakers.count == 3 && saved.tracks.count == 2 && saved.summary != nil, "speakers, tracks and notes like a normal stop")
    check(ChunkedTrackWriter.chunks(in: folder, channel: .mic).isEmpty, "chunks encoded")
    check(!FileManager.default.fileExists(atPath: orphan.path), "a sliver of audio without a meeting row is removed")
    let recovered = fakes.store.rows[lostID]
    check(recovered?.title.hasPrefix("Recovered recording from ") == true && recovered?.segments.map(\.text) == MeetingFixture.utterances.map(\.text)
              && recovered?.tracks.count == 2 && abs((recovered?.endedAt?.timeIntervalSince(recovered?.startedAt ?? Date()) ?? 0) - MeetingFixture.length) < 0.1,
          "audio without a row becomes a recovered meeting with its transcript: \(String(describing: recovered?.title))")
    let reencoded = fakes.store.rows[encodedID]
    check(reencoded?.title.hasPrefix("Recovered recording from ") == true && reencoded?.tracks.count == 2
              && abs((reencoded?.duration ?? 0) - MeetingFixture.length) < 0.2 && reencoded?.segments.count == MeetingFixture.utterances.count,
          "final files without a row are recovered too, with their length and transcript: \(String(describing: reencoded?.duration)) \(reencoded?.segments.count ?? -1)")
    check(fakes.flowBar.notifications.filter { $0.id == "meeting.recovered" }.count >= 3, "a card says each recording was recovered")
    check(recorder.state == .idle, "idle after recovery")
}

/// The real thing: a child process records a meeting into a real store and is killed with SIGKILL mid-sentence. The
/// next launch (this process, on the child's folder) finds the audio and the saved transcript and finishes the meeting.
@MainActor private func meetingKilledMidRecording() {
    let base = SuperFlowPaths.support.appendingPathComponent("killed-meeting-\(UUID().uuidString)", isDirectory: true)
    guard let line = CrashChild.runAndKill("meeting", base: base), let id = UUID(uuidString: line) else {
        check(false, "the child recorded and was killed"); return
    }
    let savedBase = SuperFlowPaths.base
    SuperFlowPaths.base = base
    defer { SuperFlowPaths.base = savedBase }
    let store = SQLiteStore.open()
    check(store.openingNotice == nil, "the store survived the kill")
    let folder = SuperFlowPaths.meetingAudio(id)
    let recorded = AudioChannel.allCases.map { ChunkedTrackWriter.read(folder: folder, channel: $0).count }
    check(recorded.allSatisfy { $0 >= 8 * AudioClip.sampleRate }, "every sample written before the kill is on disk: \(recorded)")
    check(store.meeting(id)?.endedAt == nil && store.meeting(id)?.segments.isEmpty == false, "the row and its saved transcript are there")

    let fakes = MeetingFakes()
    defer { fakes.restore() }
    Services.meetings = store
    let recorder = MeetingRecorder()
    recorder.recoverInterruptedMeetings()
    _ = complete(60) { await recorder.waitForProcessing() }
    guard let meeting = store.meeting(id) else { check(false, "recovered meeting kept"); return }
    let expected = MeetingFixture.utterances.filter { $0.start + $0.duration <= 8.5 }.map(\.text)
    check(meeting.segments.map(\.text) == expected, "the transcript is complete up to the kill: \(meeting.segments.map(\.text))")
    check(meeting.endedAt != nil && meeting.tracks.count == 2 && meeting.tracks.allSatisfy { $0.duration >= 8 }, "ended, with both final tracks")
    check(ChunkedTrackWriter.chunks(in: folder, channel: .mic).isEmpty && fakes.flowBar.notifications.contains { $0.id == "meeting.recovered" },
          "chunks encoded, and the user is told")
}

/// Finalizing is interrupted after the new file went in, halfway through deleting the chunks: running it again keeps
/// the complete file instead of re-encoding the leftover chunks over it.
@MainActor private func meetingInterruptedFinalize() {
    let folder = meetingTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let writer = ChunkedTrackWriter(folder: folder, channel: .mic)
    try? writer.append([Float](repeating: 0.2, count: 65 * AudioClip.sampleRate))
    writer.close()
    let chunks = ChunkedTrackWriter.chunks(in: folder, channel: .mic)
    guard case .success(let track?)? = Result(catching: { try MeetingAudioFiles.finalize(folder: folder, channel: .mic) }) as Result? else {
        check(false, "first finalize"); return
    }
    // Put the state back to "file in, marker written, first chunk deleted" by recreating the later chunks and the marker.
    for chunk in chunks.dropFirst() { FileManager.default.createFile(atPath: chunk.path, contents: Data(count: 30 * AudioClip.sampleRate * 2)) }
    FileManager.default.createFile(atPath: folder.appendingPathComponent("mic.encoded").path, contents: nil)
    let again = try? MeetingAudioFiles.finalize(folder: folder, channel: .mic)
    check(abs((again?.duration ?? 0) - track.duration) < 0.1, "the complete file is kept: \(String(describing: again?.duration)) vs \(track.duration)")
    check(ChunkedTrackWriter.chunks(in: folder, channel: .mic).isEmpty
              && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("mic.encoded").path), "leftover chunks and the marker go")

    // A crash while encoding leaves a partial file under another name: the chunks stay and the next run encodes them.
    let second = meetingTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: second) }
    try? ChunkedTrackWriter(folder: second, channel: .system).append([Float](repeating: 0.2, count: 3 * AudioClip.sampleRate))
    FileManager.default.createFile(atPath: second.appendingPathComponent("system.encoding.m4a").path, contents: Data([1, 2, 3]))
    let encoded = try? MeetingAudioFiles.finalize(folder: second, channel: .system)
    check(abs((encoded?.duration ?? 0) - 3) < 0.01 && !FileManager.default.fileExists(atPath: second.appendingPathComponent("system.encoding.m4a").path),
          "a half-written encode is replaced")
}

@MainActor private func meetingSystemAudioDenied() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let recorder = MeetingRecorder()
    fakes.audio.systemError = AudioError.permissionDenied
    guard case .success(let meeting)? = complete(10, { try await recorder.start(nil) }) else { check(false, "mic-only recording starts"); return }
    check(fakes.flowBar.notifications.map(\.id) == ["meeting.systemAudioOff"] && fakes.flowBar.notifications.first?.actions == ["Turn on"],
          "a card says only the mic is recorded: \(fakes.flowBar.notifications.map(\.id))")
    fakes.audio.feed(MeetingFixture.frames(base: 100, to: 3))
    meetingWaitUntil(5) { recorder.currentMeeting?.segments.isEmpty == false }
    _ = complete(10) { await recorder.stop() }
    _ = complete(30) { await recorder.waitForProcessing() }
    check(fakes.store.rows[meeting.id]?.segments.first?.text == MeetingFixture.utterances[0].text, "and the mic is transcribed")
}

/// The disk fills mid-meeting: the recording stops by itself, keeps what it has, and says so; with too little space a
/// recording doesn't start.
@MainActor private func meetingDiskFull() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let recorder = MeetingRecorder()
    recorder.monitorInterval = 0.05
    var free: Int64 = 10 << 30
    recorder.freeSpace = { free }
    guard case .success(let meeting)? = complete(10, { try await recorder.start(nil) }) else { check(false, "recording starts"); return }
    fakes.audio.feed(MeetingFixture.frames(base: 100, to: 6))
    meetingWaitUntil(5) { recorder.currentMeeting?.segments.count == 2 }
    free = 10 << 20
    check(meetingWaitUntil(5) { recorder.currentMeeting == nil }, "the recording stopped by itself")
    _ = complete(30) { await recorder.waitForProcessing() }
    let row = fakes.store.rows[meeting.id]
    check(row?.endedAt != nil && (row?.segments.count ?? 0) >= 2 && row?.tracks.count == 2, "everything recorded so far is kept")
    check(fakes.flowBar.notifications.last?.id == "meeting.storageFull" && fakes.audio.micHolders == 0, "a card says why; the mic is released")
    if case .failure(let error)? = complete(10, { try await recorder.start(nil) }) {
        check(error as? MeetingRecorderError == .storageFull, "no new recording without space")
    } else { check(false, "start refused on a full disk") }
    check(recorder.state == .idle && fakes.store.rows.count == 1, "nothing half-started")

    // A write the disk refuses stops the recording the same way.
    free = 10 << 30
    let unwritable = MeetingRecorder()
    guard case .success(let second)? = complete(10, { try await unwritable.start(nil) }) else { check(false, "second recording starts"); return }
    try? FileManager.default.removeItem(at: SuperFlowPaths.meetingAudio.appendingPathComponent(second.id.uuidString))
    fakes.audio.feed(MeetingFixture.frames(base: 200, to: 2))
    check(meetingWaitUntil(5) { unwritable.currentMeeting == nil }, "a refused write stops the recording")
    _ = complete(30) { await unwritable.waitForProcessing() }
    check(fakes.store.rows[second.id]?.endedAt != nil, "the meeting is closed properly")
}

/// The microphone goes quiet mid-meeting (unplugged): it is restarted; if it stays quiet a card says so. Then the Mac
/// goes to sleep: the recording stops properly instead of leaving a gap.
@MainActor private func meetingMicLostAndSleep() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let recorder = MeetingRecorder()
    recorder.monitorInterval = 0.05
    recorder.micSilenceLimit = 0.3
    guard case .success(let meeting)? = complete(10, { try await recorder.start(nil) }) else { check(false, "recording starts"); return }
    fakes.audio.feed(MeetingFixture.frames(base: 100, to: 1))
    check(meetingWaitUntil(3) { fakes.audio.micStarts == 2 }, "a silent microphone is restarted (\(fakes.audio.micStarts) starts)")
    check(fakes.audio.micHolders == 1, "still holding it once")
    check(meetingWaitUntil(3) { fakes.flowBar.notifications.contains { $0.id == "meeting.micLost" } }, "still silent: a card says so")

    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
    check(meetingWaitUntil(5) { recorder.currentMeeting == nil }, "sleep stops the recording")
    _ = complete(30) { await recorder.waitForProcessing() }
    check(fakes.store.rows[meeting.id]?.endedAt != nil && fakes.flowBar.notifications.last?.id == "meeting.stoppedForSleep" && fakes.audio.micHolders == 0,
          "saved and explained")
}

/// The engine wasn't ready during the meeting and the notes model failed: the transcript and audio are kept, and
/// "Retry transcript" / "Generate summary" fill them in later.
@MainActor private func meetingRetries() {
    let fakes = MeetingFakes()
    defer { fakes.restore() }
    let recorder = MeetingRecorder()
    fakes.speech.transcribeError = SpeechError.modelNotInstalled("parakeet")
    fakes.notes.isReady = false
    guard case .success(let meeting)? = complete(10, { try await recorder.start(nil) }) else { check(false, "recording starts"); return }
    fakes.audio.feed(MeetingFixture.frames(base: 100))
    let folder = SuperFlowPaths.meetingAudio(meeting.id)
    meetingWaitUntil(10) {
        AudioChannel.allCases.allSatisfy { channel in
            ChunkedTrackWriter.chunks(in: folder, channel: channel).reduce(0) { $0 + ChunkedTrackWriter.sampleCount(of: $1) }
                >= Int(MeetingFixture.length) * AudioClip.sampleRate - 640
        }
    }
    _ = complete(10) { await recorder.stop() }
    _ = complete(30) { await recorder.waitForProcessing() }
    var row = fakes.store.rows[meeting.id]
    check(row?.segments.isEmpty == true && row?.summary == nil && row?.tracks.count == 2, "no transcript, no notes, but the audio is kept")

    if case .failure(let error)? = complete(30, { try await recorder.retryTranscript(of: meeting.id) }) {
        check(error as? SpeechError == .modelNotInstalled("parakeet"), "a retry that still can't transcribe says why")
    } else { check(false, "retry without an engine must fail") }
    fakes.speech.transcribeError = nil
    if case .failure(let error)? = complete(30, { try await recorder.retryTranscript(of: meeting.id) }) { check(false, "retry failed: \(error)") }
    row = fakes.store.rows[meeting.id]
    check(row?.segments.map(\.text) == MeetingFixture.utterances.map(\.text), "the transcript comes back from the saved audio: \(row?.segments.map(\.text) ?? [])")
    check(row?.speakers.count == 3, "speakers too")
    check(row?.summary == nil && recorder.state == .idle, "still no notes without the model")

    if case .failure(let error)? = complete(30, { try await recorder.regenerateNotes(of: meeting.id) }) {
        check(error is MeetingNotesError, "Generate summary without a model says why: \(error)")
    } else { check(false, "notes without a model must fail") }
    fakes.notes.isReady = true
    if case .failure(let error)? = complete(30, { try await recorder.regenerateNotes(of: meeting.id) }) { check(false, "regenerate failed: \(error)") }
    check(fakes.store.rows[meeting.id]?.summary != nil && !fakes.store.items.isEmpty, "Generate summary writes the notes and the tasks")
    if case .failure(let error)? = complete(10, { try await recorder.retryTranscript(of: UUID()) }) {
        check(error is StoreError, "an unknown meeting is refused")
    } else { check(false, "unknown meeting must fail") }
}

/// The child process of `meetingKilledMidRecording`: records 8 s of the fixture into a real store, prints the meeting id
/// once its transcript is saved, and waits to be killed.
@MainActor func meetingCrashChild() -> Never {
    let store = SQLiteStore.open()
    let fakes = MeetingFakes()
    Services.meetings = store
    let recorder = MeetingRecorder()
    recorder.persistInterval = 0.05
    guard case .success(let meeting)? = complete(10, { try await recorder.start(nil) }) else { exit(2) }
    fakes.audio.feed(MeetingFixture.frames(base: 100, to: 8))
    meetingWaitUntil(10) { (store.meeting(meeting.id)?.segments.count ?? 0) >= 2 }
    print(CrashChild.ready + meeting.id.uuidString)
    while true { RunLoop.main.run(until: Date().addingTimeInterval(1)) }
}

// MARK: - Speakers

@MainActor private func meetingSpeakers() {
    let a = UUID(), b = UUID()
    var meeting = Meeting(title: "Sync", segments: [
        TranscriptSegment(channel: .mic, start: 0, end: 2, text: "Hello."),
        TranscriptSegment(channel: .system, start: 3, end: 5, text: "Hi there."),
        TranscriptSegment(channel: .system, start: 6, end: 8, text: "Morning."),
        TranscriptSegment(channel: .system, start: 9, end: 11, text: "Shall we start?"),
        TranscriptSegment(channel: .system, start: 20, end: 21, text: "Bye."),
    ])
    meeting.summary = MeetingSummary(title: "Sync", summary: "", actionItems: [ActionItem(text: "Send notes", owner: "Speaker 1")])
    meeting.assignSpeakers(voices: [TranscriptSegment(channel: .system, speakerID: a, start: 2.8, end: 5.2, text: ""),
                                    TranscriptSegment(channel: .system, speakerID: b, start: 5.9, end: 8.1, text: ""),
                                    TranscriptSegment(channel: .system, speakerID: a, start: 8.9, end: 11, text: "")])
    check(meeting.speakers.map(\.label) == ["You", "Speaker 1", "Speaker 2", "Them"], "You, voices in order, Them for the unmatched")
    check(speakerLines(meeting) == ["You", "Speaker 1", "Speaker 2", "Speaker 1", "Them"], "segments take the overlapping voice")

    let block = meeting.segments[2].id
    meeting.assignBlock(containing: block, to: "Sam")
    check(speakerLines(meeting) == ["You", "Speaker 1", "Sam", "Speaker 1", "Them"] && !meeting.speakers.contains { $0.label == "Speaker 2" },
          "update only this block; the emptied voice goes")
    let first = meeting.speakers.first { $0.label == "Speaker 1" }!.id
    meeting.renameSpeaker(first, to: "Priya")
    check(speakerLines(meeting) == ["You", "Priya", "Sam", "Priya", "Them"], "update everywhere")
    check(meeting.summary?.actionItems.first?.owner == "Priya", "the voice's tasks follow the name")
    let sam = meeting.speakers.first { $0.displayName == "Sam" }!.id
    meeting.renameSpeaker(sam, to: "priya")
    check(speakerLines(meeting) == ["You", "Priya", "Priya", "Priya", "Them"] && meeting.speakers.count == 3, "same name merges the voices")
    let before = meeting.speakers
    meeting.assignSpeakers(voices: [])
    check(meeting.speakers == before, "a re-run never overwrites named speakers")

    var undiarized = Meeting(title: "x", segments: [TranscriptSegment(channel: .mic, start: 0, end: 1, text: "a"),
                                                     TranscriptSegment(channel: .system, start: 2, end: 3, text: "b")])
    undiarized.assignSpeakers(voices: [])
    check(undiarized.speakers.map(\.label) == ["You", "Them"] && undiarized.segments.allSatisfy { $0.speakerID != nil }, "no diarizer: You and Them")
}

// MARK: - Notes

@MainActor private func meetingSummarizer() {
    let model = MeetingFakeNotesModel()
    model.inputWordBudget = 130
    let summarizer = MeetingSummarizer(model: model)
    // 40 segments of 10 words (13 with the line's timestamp and label): four chunks. Each chunk's notes name its topic.
    let topics = ["roadmap", "hiring", "pricing", "Android"]
    let segments = (0..<40).map { i in
        TranscriptSegment(channel: i % 2 == 0 ? .mic : .system, start: Double(i) * 5, end: Double(i) * 5 + 4,
                          text: "We talked about the \(topics[i / 10]) topic in detail again today")
    }
    var meeting = Meeting(title: "Weekly product sync", startedAt: Date(timeIntervalSince1970: 1_800_000_000), calendarEventID: "evt-1",
                          segments: segments)
    model.extract = { input in
        let topic = topics.first { input.contains($0) } ?? "nothing"
        return #"{"key_points": ["The \#(topic) topic was talked about in detail."], "decisions": [], "action_items": [], "open_questions": []}"#
    }
    model.write = #"{"title": "Roadroom strategy", "summary": "The roadmap and hiring topics were talked about."}"#

    if case .success(let notes)? = complete(60, { try await summarizer.map(Array(segments.prefix(10))) }) {
        check(notes.summary == "- The roadmap topic was talked about in detail.", "map returns the chunk's notes: \(notes.summary)")
    } else { check(false, "map") }
    guard case .success(let summary)? = complete(60, { try await summarizer.summarize(meeting) }) else { check(false, "summarize"); return }
    check(model.calls.filter { $0 == .extract }.count == 4, "chunks mapped during the meeting are not mapped again (\(model.calls))")
    check(model.calls.filter { $0 == .write }.count == 1, "one reduce call")
    check(summary.title == "Weekly product sync", "a calendar title is kept")
    check(summary.summary == "The roadmap and hiring topics were talked about.", "grounded summary kept")

    meeting.calendarEventID = nil
    meeting.title = "Untitled note"
    if case .success(let untitled)? = complete(60, { try await summarizer.summarize(meeting) }) {
        check(untitled.title == "Untitled note", "an invented title word is refused (\"Roadroom\")")
    } else { check(false, "summarize untitled") }

    // Many key points are condensed until they fit.
    model.extract = { input in
        let topic = topics.first { input.contains($0) } ?? "nothing"
        return #"{"key_points": ["The \#(topic) topic was talked about in detail again today.", "We talked about \#(topic) again.", "The \#(topic) topic came up today in detail."]}"#
    }
    model.condense = { input in
        let topic = topics.first { input.contains($0) } ?? "nothing"
        return #"{"key_points": ["The \#(topic) topic was talked about."]}"#
    }
    let fresh = MeetingSummarizer(model: model)
    model.calls = []
    if case .success(let condensed)? = complete(60, { try await fresh.summarize(meeting) }) {
        check(model.calls.contains(.condense) && condensed.summary.contains("roadmap"), "long notes are condensed: \(model.calls)")
    } else { check(false, "condense") }

    // Guards.
    model.isReady = false
    if case .failure(let error)? = complete(60, { try await fresh.summarize(meeting) }) {
        check(error as? MeetingNotesError == .modelNotReady, "model not ready")
    } else { check(false, "not ready must throw") }
    model.isReady = true
    if case .failure(let error)? = complete(60, { try await fresh.summarize(Meeting(title: "Empty")) }) {
        check(error as? MeetingNotesError == .noTranscript && error.localizedDescription == "No transcript or audio available for a summary",
              "no transcript")
    } else { check(false, "empty must throw") }
    if case .failure(let error)? = complete(60, { try await fresh.summarize(Meeting(title: "Short", segments: [TranscriptSegment(start: 0, end: 1, text: "Hi all.")])) }) {
        check(error as? MeetingNotesError == .tooShort && error.localizedDescription == "The meeting was too short to summarize.", "too short")
    } else { check(false, "short must throw") }

    // Ask anything: the chunk that shares words with the question goes to the model.
    model.answer = { "<think>search</think> " + $0 }
    if case .success(let answer)? = complete(60, { try await fresh.ask("What about Android?", about: meeting) }) {
        check(answer.hasSuffix("Question: What about Android?") && answer.contains("Android topic") && !answer.contains("<think>"),
              "retrieval picks the matching chunk")
    } else { check(false, "ask") }
}

private func meetingExport() {
    let meeting = sampleMeeting()
    let markdown = MeetingExport.text(meeting, format: .markdown)
    check(markdown.hasPrefix("# Design review\n\n"), "title heading")
    check(markdown.contains("· 1 h 0 min · Zoom\nParticipants: Priya"), "date, duration, platform and participants")
    for section in ["## Summary\n\nRoadmap agreed.", "## Key decisions\n\n- Ship Thursday", "## Follow-ups\n\n- Confirm with Priya",
                    "## Notes\n\nRemember the colour tokens.", "## Transcript\n\n**Udaya** (00:00): Let's start with the roadmap.\n\n**Speaker 1** (00:03): We ship Thursday."] {
        check(markdown.contains(section), "markdown has \(section.prefix(20))")
    }
    check(markdown.contains("## Action items\n\n- [ ] Send the deck — Udaya, due "), "action items as a checklist")
    let plain = MeetingExport.text(meeting, format: .plainText, includeTranscript: false)
    check(plain.hasPrefix("Design review\n") && plain.contains("SUMMARY\n\nRoadmap agreed.") && !plain.contains("#") && !plain.contains("TRANSCRIPT"),
          "plain text without the transcript")
    var done = meeting.summary!.actionItems[0]
    done.isCompleted = true
    check(MeetingExport.checklist([done]).hasPrefix("- [x] Send the deck"), "completed items are ticked")
    var odd = meeting
    odd.title = "Q3/Q4: plan?"
    check(MeetingExport.fileName(for: odd, format: .markdown).hasPrefix("Q3 Q4  plan ") && MeetingExport.fileName(for: odd, format: .markdown).hasSuffix(".md"),
          "file name without path characters")
    let url = meetingTemporaryFolder().appendingPathComponent(MeetingExport.fileName(for: meeting, format: .markdown))
    try? MeetingExport.write(meeting, format: .markdown, to: url)
    check((try? String(contentsOf: url, encoding: .utf8)) == markdown, "written file is the markdown")
    // A private pasteboard, never the user's clipboard.
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("superflow-selftest-\(UUID().uuidString)"))
    MeetingExport.copy(markdown, to: pasteboard)
    check(pasteboard.string(forType: .string) == markdown, "copy puts the text on the pasteboard")
    pasteboard.releaseGlobally()
}

// MARK: - Retention

@MainActor private func meetingAudioRetention() {
    let fakes = MeetingFakes()
    defer { fakes.restore(); Defaults.reset(.meetingAudioRetentionDays) }
    let recorder = MeetingRecorder()
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    func meeting(endedDaysAgo days: Double) -> Meeting {
        let ended = now.addingTimeInterval(-days * 86_400)
        let meeting = Meeting(title: "m", startedAt: ended.addingTimeInterval(-3600), endedAt: ended,
                              tracks: [AudioTrack(channel: .mic, file: "mic.m4a", duration: 3600, byteSize: 10)],
                              segments: [TranscriptSegment(start: 0, end: 1, text: "kept")], notes: "kept too")
        try? Data([1]).write(to: SuperFlowPaths.meetingAudio(meeting.id).appendingPathComponent("mic.m4a"))
        try? fakes.store.save(meeting)
        return meeting
    }
    let old = meeting(endedDaysAgo: 31), recent = meeting(endedDaysAgo: 5)
    var untranscribed = meeting(endedDaysAgo: 40)
    untranscribed.segments = []
    try? fakes.store.save(untranscribed)
    check(Defaults[.meetingAudioRetentionDays] == 30, "owner decision: 30 days by default")
    check(recorder.pruneAudio(now: now) == [old.id], "audio older than 30 days is deleted")
    check(fakes.store.rows[untranscribed.id]?.hasAudio == true, "but not when it's the meeting's only record (nothing was transcribed)")
    check(!FileManager.default.fileExists(atPath: SuperFlowPaths.meetingAudio.appendingPathComponent(old.id.uuidString).path), "old audio folder gone")
    check(fakes.store.rows[old.id]?.audioDeletedAt == now && fakes.store.rows[old.id]?.segments.first?.text == "kept"
          && fakes.store.rows[old.id]?.notes == "kept too", "transcript and notes kept")
    check(fakes.store.rows[recent.id]?.hasAudio == true, "recent audio kept")
    Defaults[.meetingAudioRetentionDays] = RetentionPolicy.keepForever
    _ = meeting(endedDaysAgo: 400)
    check(recorder.pruneAudio(now: now).isEmpty, "\"Never delete\" keeps audio")
}

// MARK: - Real model (gated)

/// Minimal greedy llama.cpp generation for the smoke test (CleanupKit owns the app's LLM runtime).
@MainActor private final class MeetingLlamaNotesModel: NotesLanguageModel {
    let modelID = ModelCatalog.qwen35_4B.id
    let inputWordBudget = 1200
    var isReady: Bool { true }
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer

    init?(url: URL) {
        _ = LlamaEngine.backendReady
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let model = llama_model_load_from_file(url.path, modelParams), let vocab = llama_model_get_vocab(model) else { return nil }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 8192
        contextParams.n_batch = 2048
        guard let context = llama_init_from_model(model, contextParams) else { llama_model_free(model); return nil }
        self.model = model
        self.context = context
        self.vocab = vocab
    }

    func close() {
        llama_free(context)
        llama_model_free(model)
    }

    func complete(_ request: NotesRequest) async throws -> String {
        // Qwen chat format with an empty reasoning block (non-thinking).
        let prompt = "<|im_start|>system\n\(request.instruction)<|im_end|>\n<|im_start|>user\n\(request.input)<|im_end|>\n"
            + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        let utf8 = Array(prompt.utf8CString)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 16)
        let count = llama_tokenize(vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(tokens.count), true, true)
        guard count > 0 else { throw SpeechError.failed("tokenize") }
        tokens = Array(tokens.prefix(Int(count)))
        llama_memory_clear(llama_get_memory(context), true)
        var start = 0
        while start < tokens.count {
            let n = min(2048, tokens.count - start)
            let status = tokens.withUnsafeMutableBufferPointer { llama_decode(context, llama_batch_get_one($0.baseAddress! + start, Int32(n))) }
            guard status == 0 else { throw SpeechError.failed("decode \(status)") }
            start += n
        }
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        defer { llama_sampler_free(sampler) }
        var bytes: [UInt8] = []
        for _ in 0..<900 {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 256)
            let length = llama_token_to_piece(vocab, token, &piece, 256, 0, false)
            if length > 0 { bytes += piece.prefix(Int(length)).map { UInt8(bitPattern: $0) } }
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            if status != 0 { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

@MainActor private func meetingNotesRealModel() {
    let folders = (ProcessInfo.processInfo.environment["SUPERFLOW_DEV_MODELS"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    guard let gguf = folders.map({ $0.appendingPathComponent(ModelCatalog.qwen35_4B.fileName) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        print("  (skipped: no \(ModelCatalog.qwen35_4B.fileName) in SUPERFLOW_DEV_MODELS)"); return
    }
    let loadStarted = Date()
    guard let model = MeetingLlamaNotesModel(url: gguf) else { check(false, "Qwen3.5-4B loads"); return }
    defer { model.close() }
    print("  notes model loaded in \(String(format: "%.1f", Date().timeIntervalSince(loadStarted))) s")
    let you = Speaker(label: "You", channel: .mic), priya = Speaker(label: "Speaker 1", name: "Priya", channel: .system)
    let sam = Speaker(label: "Speaker 2", name: "Sam", channel: .system)
    let lines: [(Speaker, String)] = [
        (you, "Thanks for joining. Let's go through the launch plan for the mobile app."),
        (priya, "Engineering is on track, but the Android build still crashes on older phones."),
        (sam, "Marketing wants a date. Can we commit to launching in the week of the 14th?"),
        (you, "If the crash is fixed by Friday, yes. Let's push the launch to the week of the 14th."),
        (priya, "I can have the crash fix and the pricing proposal ready by Friday."),
        (sam, "Great. I'll own the onboarding metrics review and share it next Tuesday."),
        (you, "One open question is whether we offer a free tier at launch. Let's decide that next week."),
        (priya, "Also, support needs the FAQ updated before launch. I'm not sure who owns that."),
        (you, "Okay, so the launch moves to the week of the 14th, and we revisit the free tier next week."),
    ]
    let segments = lines.enumerated().map { i, line in
        TranscriptSegment(channel: line.0.channel, speakerID: line.0.id, start: Double(i) * 12, end: Double(i) * 12 + 10, text: line.1)
    }
    let meeting = Meeting(title: "Untitled note", startedAt: Date(timeIntervalSince1970: 1_800_000_000), endedAt: Date(timeIntervalSince1970: 1_800_000_120),
                          speakers: [you, priya, sam], segments: segments, notes: "Check the Android crash numbers.")
    let summarizer = MeetingSummarizer(model: model)
    let started = Date()
    switch complete(600, { try await summarizer.summarize(meeting) }) {
    case .success(let summary)?:
        print("  notes in \(String(format: "%.1f", Date().timeIntervalSince(started))) s — title: \(summary.title)")
        print("  summary: \(summary.summary.replacingOccurrences(of: "\n", with: " / "))")
        print("  decisions: \(summary.decisions)")
        print("  actions: \(summary.actionItems.map { "\($0.text) [\($0.owner ?? "-"), \($0.due.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "-")]" })")
        print("  follow-ups: \(summary.followUps)")
        check(!summary.summary.isEmpty, "the real model writes a grounded summary")
        check(!summary.decisions.isEmpty || !summary.actionItems.isEmpty, "decisions or action items found")
        check(summary.actionItems.allSatisfy { $0.owner.map { ["You", "Priya", "Sam"].contains($0) } ?? true }, "owners are people in the meeting")
    case .failure(let error)?: check(false, "real-model notes failed: \(error.localizedDescription)")
    case nil: check(false, "real-model notes timed out")
    }
    if case .success(let answer)? = complete(300, { try await summarizer.ask("When is the launch now?", about: meeting) }) {
        print("  ask: \(answer)")
        check(answer.contains("14"), "ask answers from the transcript")
    } else { check(false, "ask with the real model") }
}

import Combine
import Foundation
import SuperFlowCore

/// One speech service owns the engines (local-models.md §8.3): Parakeet for its 25 languages, whisper.cpp for the rest
/// and on Intel, Silero VAD in front of both, and a priority gate so dictation jobs go before queued meeting jobs.
///
/// Times in returned segments use the time base of the clips passed in (`AudioClip.startTime` plus the offset).
@MainActor
public final class SpeechService: SpeechRecognizing {
    public static let shared = SpeechService(models: ModelManager.shared)

    private let models: ModelManaging
    private var parakeet: (id: String, engine: ParakeetEngine)?
    private var whisper: (id: String, engine: WhisperEngine)?
    private var diarizer: (url: URL, engine: SpeakerDiarizer)?
    public private(set) var activeEngineID: String?
    private let gate = PriorityGate()
    private var modelChanges: AnyCancellable?
    private var memoryPressure: DispatchSourceMemoryPressure?

    public init(models: ModelManaging) {
        self.models = models
        modelChanges = models.changes.sink { [weak self] id in
            MainActor.assumeIsolated { self?.modelChanged(id) }
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                Log.speech.info("Critical memory pressure: unloading speech engines until the next dictation")
                self?.unload()
            }
        }
        source.resume()
        memoryPressure = source
    }

    public var availableEngines: [String] {
        models.catalog.filter { $0.kind == .asr && models.state(of: $0.id) == .installed && Self.canRun($0) }.map(\.id)
    }

    static func canRun(_ model: ModelDescriptor) -> Bool {
        model.engine == "whisper" || (model.engine == "fluidaudio" && Machine.isAppleSilicon)
    }

    // MARK: Engines

    public func prepare(modelID: String) async throws {
        guard let model = models.catalog.first(where: { $0.id == modelID }), model.kind == .asr else {
            throw SpeechError.modelNotInstalled(modelID)
        }
        guard Self.canRun(model) else { throw SpeechError.engineUnavailable("\(model.name) needs a Mac with Apple silicon.") }
        guard let url = models.location(of: modelID) else { throw SpeechError.modelNotInstalled(modelID) }
        if model.engine == "fluidaudio" {
            if parakeet?.id != modelID {
                let engine = ParakeetEngine(directory: url)
                try await engine.load()
                await engine.warm()
                let previous = parakeet
                parakeet = (modelID, engine)
                await previous?.engine.unload()
            }
        } else if whisper?.id != modelID {
            let engine = WhisperEngine(modelURL: url)
            try await engine.load()
            await engine.warm()
            let previous = whisper
            whisper = (modelID, engine)
            await previous?.engine.unload()
        }
        activeEngineID = modelID
        Log.speech.info("Prepared \(modelID, privacy: .public)")
    }

    public func unload() {
        let engines = (parakeet?.engine, whisper?.engine)
        parakeet = nil
        whisper = nil
        diarizer = nil
        activeEngineID = nil
        Task {
            await engines.0?.unload()
            await engines.1?.unload()
        }
    }

    /// The preferred engine when nothing is loaded yet: the dictation setting, else the best installed model this Mac runs.
    private func ensureEngine() async throws {
        guard parakeet == nil, whisper == nil else { return }
        let installed = availableEngines
        let preferred = [Defaults[.asrModelID]] + installed.sorted { rank($0) > rank($1) }
        guard let id = preferred.first(where: installed.contains) else {
            throw SpeechError.modelNotInstalled(Defaults[.asrModelID])
        }
        try await prepare(modelID: id)
    }

    private func rank(_ id: String) -> Int64 {
        guard let model = models.catalog.first(where: { $0.id == id }) else { return 0 }
        return (model.engine == "fluidaudio" ? 1 << 40 : 0) + model.bytes
    }

    private enum Engine {
        case parakeet(ParakeetEngine)
        case whisper(WhisperEngine)
    }

    /// Parakeet when it covers the requested languages, else the multilingual Whisper fallback (loaded on first use),
    /// else whatever is loaded.
    private func engine(for languages: [String]) async throws -> Engine {
        try await ensureEngine()
        let parakeetFits = SpeechLanguages.parakeetCovers(languages)
        if let parakeet, parakeetFits, activeEngineID == parakeet.id || whisper == nil { return .parakeet(parakeet.engine) }
        if let whisper, activeEngineID == whisper.id || !parakeetFits { return .whisper(whisper.engine) }
        if !parakeetFits, let fallback = try await loadFallbackWhisper() { return .whisper(fallback) }
        if let parakeet { return .parakeet(parakeet.engine) }
        if let whisper { return .whisper(whisper.engine) }
        throw SpeechError.engineUnavailable("No speech engine is loaded.")
    }

    /// The multilingual fallback (`fallbackASRModelID`, else the largest installed Whisper model), kept loaded beside Parakeet.
    private func loadFallbackWhisper() async throws -> WhisperEngine? {
        if let whisper { return whisper.engine }
        let candidates = models.catalog.filter { $0.engine == "whisper" && $0.kind == .asr && models.state(of: $0.id) == .installed }
        guard let pick = candidates.first(where: { $0.id == Defaults[.fallbackASRModelID] }) ?? candidates.max(by: { $0.bytes < $1.bytes }),
              let url = models.location(of: pick.id) else { return nil }
        let engine = WhisperEngine(modelURL: url)
        try await engine.load()
        await engine.warm()
        whisper = (pick.id, engine)
        Log.speech.info("Loaded the multilingual fallback \(pick.id, privacy: .public)")
        return engine
    }

    /// A deleted model leaves memory; the main dictation model replaces the bootstrap one as soon as it is installed.
    private func modelChanged(_ id: String) {
        let installed = models.state(of: id) == .installed
        if !installed {
            if parakeet?.id == id { let old = parakeet?.engine; parakeet = nil; Task { await old?.unload() } }
            if whisper?.id == id { let old = whisper?.engine; whisper = nil; Task { await old?.unload() } }
            if activeEngineID == id { activeEngineID = nil }
            if id == ModelCatalog.diarization.id { diarizer = nil }
        } else if id == Defaults[.asrModelID], activeEngineID != nil, activeEngineID != id,
                  let model = models.catalog.first(where: { $0.id == id }), Self.canRun(model) {
            Task { try? await self.prepare(modelID: id) }
        }
    }

    // MARK: Recognition

    public func transcribe(_ audio: AudioClip, options: TranscriptionOptions, priority: SpeechPriority) async throws -> Transcript {
        let vad = makeVAD()
        let regions = SpeechRegions.regions(probabilities: vad.probabilities(audio.samples, continuing: false), window: vad.window,
                                            totalSamples: audio.samples.count)
        guard let first = regions.first, let last = regions.last,
              regions.reduce(0, { $0 + $1.count }) >= Int(VADParameters.dictation.minimumSpeech * Double(AudioClip.sampleRate)) else {
            throw SpeechError.noSpeech
        }
        let span = first.lowerBound..<last.upperBound
        let clip = AudioClip(samples: Array(audio.samples[span]),
                             startTime: audio.startTime + Double(span.lowerBound) / Double(AudioClip.sampleRate))
        let speechSeconds = Double(regions.reduce(0) { $0 + $1.count }) / Double(AudioClip.sampleRate)
        let quiet = TranscriptGuard.isQuiet(audio.samples[span])
        var language: (String, Double)?
        let transcript = try await recognise(clip, options: options, priority: priority, speechSeconds: speechSeconds, quiet: quiet,
                                             language: &language)
        guard !transcript.text.isEmpty else { throw SpeechError.noSpeech }
        return transcript
    }

    /// Runs one clip through the right engine behind the priority gate, then the guards. `language` carries a stream's
    /// detected language from segment to segment.
    private func recognise(_ clip: AudioClip, options: TranscriptionOptions, priority: SpeechPriority, speechSeconds: TimeInterval,
                           quiet: Bool, language: inout (String, Double)?) async throws -> Transcript {
        await gate.acquire(priority)
        defer { gate.release() }
        try Task.checkCancellation()
        let languages = options.languages.map(SpeechLanguages.base)
        var transcript: Transcript
        switch try await engine(for: languages) {
        case .parakeet(let engine):
            transcript = try await engine.transcribe(clip, language: languages.count == 1 ? languages[0] : nil)
            let identified = TextLanguage.identify(transcript.text, among: languages.isEmpty ? Array(SpeechLanguages.parakeet) : languages)
            transcript.language = languages.count == 1 ? languages[0] : identified.language
            transcript.languageConfidence = identified.confidence
            transcript.text = TranscriptGuard.accept(transcript.text, speechSeconds: speechSeconds, quiet: quiet)
        case .whisper(let engine):
            if language == nil {
                language = languages.count == 1 ? (languages[0], 1) : try await engine.detectLanguage(clip, among: languages)
            }
            let prompt = WhisperPrompt.make(vocabulary: options.vocabulary, previousText: options.previousText)
            transcript = try await engine.transcribe(clip, language: language?.0, prompt: prompt)
            var text = TranscriptGuard.accept(transcript.text, speechSeconds: speechSeconds, quiet: quiet)
            if text.isEmpty, !transcript.text.isEmpty, WhisperEngine.audioContext(for: clip.duration) < 1500 {
                // Guard 5: a sized audio_ctx can loop or truncate; the full window decides.
                transcript = try await engine.transcribe(clip, language: language?.0, prompt: prompt, fullWindow: true)
                text = TranscriptGuard.accept(transcript.text, speechSeconds: speechSeconds, quiet: quiet)
            }
            transcript.text = text
            transcript.languageConfidence = language?.1 ?? 1
        }
        if transcript.text.isEmpty { transcript.segments = [] }
        else if transcript.segments.count == 1 { transcript.segments[0].text = transcript.text }
        return transcript
    }

    public func transcribeIncrementally(_ audio: AsyncStream<AudioClip>, options: TranscriptionOptions, priority: SpeechPriority)
        -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let session = IncrementalSession(vad: self.makeVAD(), parameters: priority == .meeting ? .meeting : .dictation)
                do {
                    for await clip in audio {
                        try Task.checkCancellation()
                        for region in session.append(clip) {
                            if let segment = try await self.segment(session, region, options: options, priority: priority) {
                                continuation.yield(.segment(segment))
                                continuation.yield(.partial(session.text))
                            }
                        }
                        if let open = session.openRegionForPartial() {
                            let partial = try? await self.decode(session, open, options: options, priority: priority, commit: false)
                            if let partial, !partial.text.isEmpty { continuation.yield(.partial(session.text + " " + partial.text)) }
                        }
                    }
                    try Task.checkCancellation()
                    if let tail = session.finish(), let segment = try await self.segment(session, tail, options: options, priority: priority) {
                        continuation.yield(.segment(segment))
                    }
                    guard !session.segments.isEmpty else { throw SpeechError.noSpeech }
                    continuation.yield(.final(session.transcript))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error is CancellationError ? SpeechError.failed("Cancelled") : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func segment(_ session: IncrementalSession, _ region: Range<Int>, options: TranscriptionOptions,
                         priority: SpeechPriority) async throws -> TranscriptSegment? {
        guard let transcript = try await decode(session, region, options: options, priority: priority, commit: true),
              !transcript.text.isEmpty else { return nil }
        return session.segments.last
    }

    /// Decodes one region of the stream; a committed one joins the session's text and passes it on as context.
    private func decode(_ session: IncrementalSession, _ region: Range<Int>, options: TranscriptionOptions, priority: SpeechPriority,
                        commit: Bool) async throws -> Transcript? {
        guard let samples = session.samples(region) else { return nil }
        var context = options
        if context.previousText == nil || !session.text.isEmpty { context.previousText = session.text.isEmpty ? options.previousText : session.text }
        let clip = AudioClip(samples: samples, startTime: session.time(of: region.lowerBound))
        var language = session.language
        let transcript = try await recognise(clip, options: context, priority: priority,
                                             speechSeconds: Double(region.count) / Double(AudioClip.sampleRate),
                                             quiet: TranscriptGuard.isQuiet(samples[...]), language: &language)
        if commit {
            session.language = language
            session.commit(transcript, region: region)
        }
        return transcript
    }

    public func speechSegments(in audio: AudioClip) async -> [Range<Int>] {
        let vad = makeVAD()
        return SpeechRegions.regions(probabilities: vad.probabilities(audio.samples, continuing: false), window: vad.window,
                                     totalSamples: audio.samples.count, parameters: .meeting)
    }

    /// Silero when its model is on disk, else the energy gate.
    private func makeVAD() -> SpeechProbabilityModel {
        if let url = models.location(of: ModelCatalog.sileroVAD.id), let silero = try? SileroVAD(modelURL: url) { return silero }
        return EnergyVAD()
    }

    public func diarize(_ audio: AudioClip) async throws -> [TranscriptSegment] {
        let id = ModelCatalog.diarization.id
        guard let url = models.location(of: id) else { throw SpeechError.modelNotInstalled(id) }
        if diarizer?.url != url {
            let engine = SpeakerDiarizer(directory: url)
            try await engine.load()
            diarizer = (url, engine)
        }
        guard let engine = diarizer?.engine else { throw SpeechError.engineUnavailable("The speaker model isn't loaded.") }
        await gate.acquire(.meeting)
        defer { gate.release() }
        let turns = try await engine.diarize(audio.samples)
        var speakers: [String: UUID] = [:]
        return turns.map { turn in
            let speaker = speakers[turn.speaker] ?? UUID()
            speakers[turn.speaker] = speaker
            return TranscriptSegment(channel: .system, speakerID: speaker, start: audio.startTime + turn.start,
                                     end: audio.startTime + turn.end, text: "")
        }
    }
}

/// Serialises engine work: one job at a time, dictation before meeting, first come first served within a priority.
@MainActor
public final class PriorityGate {
    private var busy = false
    private var ticket = 0
    private var waiting: [(priority: SpeechPriority, ticket: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init() {}

    public func acquire(_ priority: SpeechPriority) async {
        guard busy else {
            busy = true
            return
        }
        ticket += 1
        let mine = ticket
        await withCheckedContinuation { continuation in
            waiting.append((priority, mine, continuation))
        }
    }

    public func release() {
        guard let next = waiting.indices.min(by: {
            (waiting[$0].priority > waiting[$1].priority) || (waiting[$0].priority == waiting[$1].priority && waiting[$0].ticket < waiting[$1].ticket)
        }) else {
            busy = false
            return
        }
        waiting.remove(at: next).continuation.resume()
    }
}

/// The state of one incremental transcription: the audio not yet committed, the segmenter, the committed segments
/// and when the open region was last decoded for a partial.
@MainActor
final class IncrementalSession {
    /// A partial is decoded each time the open region grew by this much.
    static let partialInterval = 1.0

    private let vad: SpeechProbabilityModel
    private var segmenter: StreamingSegmenter
    private var buffer: [Float] = []
    /// Stream sample index of `buffer[0]`.
    private var bufferStart = 0
    private var total = 0
    private var scored = 0
    private var origin: TimeInterval?
    private var lastPartialAt = 0
    private(set) var segments: [TranscriptSegment] = []
    private var confidences: [Double] = []
    var language: (String, Double)?

    init(vad: SpeechProbabilityModel, parameters: VADParameters) {
        self.vad = vad
        segmenter = StreamingSegmenter(window: vad.window, parameters: parameters)
    }

    var text: String { segments.map(\.text).joined(separator: " ") }

    var transcript: Transcript {
        let confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return Transcript(text: text, language: language?.0 ?? "", confidence: confidence, languageConfidence: language?.1 ?? 1,
                          segments: segments)
    }

    func time(of index: Int) -> TimeInterval { (origin ?? 0) + Double(index) / Double(AudioClip.sampleRate) }

    /// Adds audio; returns regions a pause just closed.
    func append(_ clip: AudioClip) -> [Range<Int>] {
        if origin == nil { origin = clip.startTime }
        buffer += clip.samples
        total += clip.samples.count
        let windowed = (total - scored) / vad.window * vad.window
        guard windowed > 0 else { return [] }
        let start = scored - bufferStart
        let probabilities = vad.probabilities(Array(buffer[start..<start + windowed]), continuing: scored > 0)
        scored += windowed
        return segmenter.push(probabilities)
    }

    /// The open region when it has grown enough since the last partial.
    func openRegionForPartial() -> Range<Int>? {
        guard let open = segmenter.open, open.count >= AudioClip.sampleRate / 2,
              open.upperBound - lastPartialAt >= Int(IncrementalSession.partialInterval * Double(AudioClip.sampleRate)) else { return nil }
        lastPartialAt = open.upperBound
        return open
    }

    /// Ends the stream: the region still open, if it holds speech.
    func finish() -> Range<Int>? {
        let rest = total - scored
        if rest > 0 {
            let padded = Array(buffer.suffix(rest)) + [Float](repeating: 0, count: vad.window - rest % vad.window)
            _ = segmenter.push(vad.probabilities(padded, continuing: scored > 0))
        }
        return segmenter.finish(totalSamples: total)
    }

    func samples(_ region: Range<Int>) -> [Float]? {
        let lower = region.lowerBound - bufferStart, upper = min(region.upperBound, total) - bufferStart
        guard lower >= 0, upper > lower else { return nil }
        return Array(buffer[lower..<upper])
    }

    func commit(_ transcript: Transcript, region: Range<Int>) {
        // Audio before the end of a committed region is never needed again.
        let drop = max(0, min(region.upperBound, scored) - bufferStart)
        buffer.removeFirst(drop)
        bufferStart += drop
        guard !transcript.text.isEmpty else { return }
        segments.append(TranscriptSegment(start: time(of: region.lowerBound), end: time(of: region.upperBound), text: transcript.text))
        confidences.append(transcript.confidence)
    }
}

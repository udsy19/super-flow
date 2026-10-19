import Combine
import Foundation
import SuperFlowCore

/// One speech service owns the engines (local-models.md §8.3): Parakeet for its 25 languages, whisper.cpp for the rest
/// and on Intel, Silero VAD in front of them, and a priority gate so dictation jobs go before queued meeting jobs. The user
/// may choose Nemotron (live English, stt-second-engine.md §5) or Apple's engine on macOS 26 (§6) for dictation;
/// meetings and the languages those don't cover stay on Parakeet or Whisper.
///
/// Times in returned segments use the time base of the clips passed in (`AudioClip.startTime` plus the offset).
@MainActor
public final class SpeechService: SpeechRecognizing {
    public static let shared = SpeechService(models: ModelManager.shared)

    private let models: ModelManaging
    private var parakeet: (id: String, engine: ParakeetEngine)?
    private var whisper: (id: String, engine: WhisperEngine)?
    private var nemotron: (id: String, engine: NemotronEngine)?
    /// An `AppleSpeechEngine` (macOS 26 only) and the one language it was loaded for.
    private var apple: (id: String, language: String, engine: AnyObject)?
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

    /// Apple's engine counts only once chosen: using it may ask the OS for a download.
    public var availableEngines: [String] {
        models.catalog.filter {
            $0.kind == .asr && models.state(of: $0.id) == .installed && Self.canRun($0) && (!$0.isBuiltIn || $0.id == Defaults[.asrModelID])
        }.map(\.id)
    }

    static func canRun(_ model: ModelDescriptor) -> Bool {
        switch model.engine {
        case "whisper": true
        case "fluidaudio", "fluidaudio-nemotron": Machine.isAppleSilicon
        case "apple": AppleSpeech.isSupported
        default: false
        }
    }

    // MARK: Engines

    public func prepare(modelID: String) async throws {
        guard let model = models.catalog.first(where: { $0.id == modelID }), model.kind == .asr else {
            throw SpeechError.modelNotInstalled(modelID)
        }
        guard Self.canRun(model) else {
            throw SpeechError.engineUnavailable(model.isBuiltIn ? "\(model.name) needs macOS 26." : "\(model.name) needs a Mac with Apple silicon.")
        }
        if model.isBuiltIn {
            try await prepareApple(model)
            activeEngineID = modelID
            Log.speech.info("Prepared \(modelID, privacy: .public)")
            return
        }
        guard let url = models.location(of: modelID) else { throw SpeechError.modelNotInstalled(modelID) }
        switch model.engine {
        case "fluidaudio":
            if parakeet?.id != modelID {
                let engine = ParakeetEngine(directory: url)
                try await engine.load()
                await engine.warm()
                let previous = parakeet
                parakeet = (modelID, engine)
                await previous?.engine.unload()
            }
        case "fluidaudio-nemotron":
            if nemotron?.id != modelID {
                let engine = NemotronEngine(directory: url)
                try await engine.load()
                await engine.warm()
                let previous = nemotron
                nemotron = (modelID, engine)
                await previous?.engine.unload()
            }
        default:
            if whisper?.id != modelID {
                let engine = WhisperEngine(modelURL: url)
                try await engine.load()
                await engine.warm()
                let previous = whisper
                whisper = (modelID, engine)
                await previous?.engine.unload()
            }
        }
        activeEngineID = modelID
        Log.speech.info("Prepared \(modelID, privacy: .public)")
    }

    /// Apple's engine for the one dictation language it supports; the OS installs that language's assets if needed.
    private func prepareApple(_ model: ModelDescriptor) async throws {
        guard #available(macOS 26, *) else { throw SpeechError.engineUnavailable("\(model.name) needs macOS 26.") }
        let languages = SpeechLanguages.requested(selected: Defaults[.selectedLanguages], autoDetect: Defaults[.autoDetectLanguage])
        guard languages.count == 1, let language = languages.first, let locale = await AppleSpeechEngine.locale(for: language) else {
            throw SpeechError.engineUnavailable("Apple's engine needs one dictation language it supports.")
        }
        if apple?.id == model.id, apple?.language == language { return }
        let engine = AppleSpeechEngine(locale: locale)
        try await engine.load()
        await engine.warm()
        apple = (model.id, language, engine)
    }

    public func unload() {
        let engines = (parakeet?.engine, whisper?.engine, nemotron?.engine)
        parakeet = nil
        whisper = nil
        nemotron = nil
        apple = nil
        diarizer = nil
        activeEngineID = nil
        Task {
            await engines.0?.unload()
            await engines.1?.unload()
            await engines.2?.unload()
        }
    }

    /// The preferred engine when nothing is loaded yet: the dictation setting, else the best installed model this Mac
    /// runs. A model that won't load (a damaged file, too little memory) doesn't stop dictation while another installed
    /// one does; the first error is thrown only when none loads.
    private func ensureEngine() async throws {
        guard parakeet == nil, whisper == nil, nemotron == nil, apple == nil else { return }
        let installed = availableEngines
        var tried: Set<String> = []
        var firstError: Error?
        for id in [Defaults[.asrModelID]] + installed.sorted(by: { rank($0) > rank($1) }) where installed.contains(id) && tried.insert(id).inserted {
            do {
                try await prepare(modelID: id)
                return
            } catch {
                Log.speech.error("\(id, privacy: .public) didn't load (\(error.localizedDescription, privacy: .public)); trying the next installed engine")
                firstError = firstError ?? error
            }
        }
        throw firstError ?? SpeechError.modelNotInstalled(Defaults[.asrModelID])
    }

    private func rank(_ id: String) -> Int64 {
        guard let model = models.catalog.first(where: { $0.id == id }) else { return 0 }
        return (model.engine == "fluidaudio" ? 1 << 40 : 0) + model.bytes
    }

    private enum Engine {
        case parakeet(ParakeetEngine)
        case whisper(WhisperEngine)
        case nemotron(NemotronEngine)
        /// An `AppleSpeechEngine`.
        case apple(AnyObject)
    }

    /// For dictation, the chosen Nemotron or Apple engine when it covers the languages (Nemotron: English only; Apple: the
    /// one language it was loaded for). Otherwise, and for meetings, Parakeet when it covers the requested languages,
    /// else the multilingual Whisper fallback (loaded on first use), else whatever is loaded.
    private func engine(for languages: [String], priority: SpeechPriority) async throws -> Engine {
        try await ensureEngine()
        if priority == .dictation {
            if let nemotron, activeEngineID == nemotron.id, Self.isEnglishOnly(languages) { return .nemotron(nemotron.engine) }
            if let apple, activeEngineID == apple.id, languages == [apple.language] { return .apple(apple.engine) }
        }
        let parakeetFits = SupportedLanguages.parakeetCovers(languages)
        if parakeet == nil, whisper == nil, parakeetFits { try await loadParakeetBeside() }
        if let parakeet, parakeetFits, activeEngineID == parakeet.id || whisper == nil { return .parakeet(parakeet.engine) }
        if let whisper, activeEngineID == whisper.id || !parakeetFits { return .whisper(whisper.engine) }
        if !parakeetFits, let fallback = try await loadFallbackWhisper() { return .whisper(fallback) }
        if let parakeet { return .parakeet(parakeet.engine) }
        if let whisper { return .whisper(whisper.engine) }
        if let nemotron { return .nemotron(nemotron.engine) }
        if let apple { return .apple(apple.engine) }
        throw SpeechError.engineUnavailable("No speech engine is loaded.")
    }

    static func isEnglishOnly(_ languages: [String]) -> Bool { !languages.isEmpty && languages.allSatisfy { $0 == "en" } }

    /// Parakeet next to a chosen Nemotron or Apple engine, for meetings and the languages those don't cover.
    private func loadParakeetBeside() async throws {
        guard let model = models.catalog.first(where: { $0.engine == "fluidaudio" && $0.kind == .asr && models.state(of: $0.id) == .installed }),
              Self.canRun(model), let url = models.location(of: model.id) else { return }
        let engine = ParakeetEngine(directory: url)
        try await engine.load()
        await engine.warm()
        parakeet = (model.id, engine)
        Log.speech.info("Loaded \(model.id, privacy: .public) beside the chosen engine")
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
            if nemotron?.id == id { let old = nemotron?.engine; nemotron = nil; Task { await old?.unload() } }
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
        let languages = options.languages.map(SupportedLanguages.base)
        var transcript: Transcript
        switch try await engine(for: languages, priority: priority) {
        case .parakeet(let engine):
            transcript = try await engine.transcribe(clip, language: languages.count == 1 ? languages[0] : nil)
            let identified = TextLanguage.identify(transcript.text, among: languages.isEmpty ? SupportedLanguages.parakeet : languages)
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
        case .nemotron(let engine):
            transcript = try await engine.transcribe(clip)
            transcript.text = TranscriptGuard.accept(transcript.text, speechSeconds: speechSeconds, quiet: quiet)
        case .apple(let box):
            guard #available(macOS 26, *), let engine = box as? AppleSpeechEngine else {
                throw SpeechError.engineUnavailable("Apple's engine needs macOS 26.")
            }
            transcript = try await engine.transcribe(clip, vocabulary: options.vocabulary)
            transcript.text = TranscriptGuard.accept(transcript.text, speechSeconds: speechSeconds, quiet: quiet)
        }
        if transcript.text.isEmpty { transcript.segments = [] }
        else if transcript.segments.count == 1 { transcript.segments[0].text = transcript.text }
        return transcript
    }

    public func transcribeIncrementally(_ audio: AsyncStream<AudioClip>, options: TranscriptionOptions, priority: SpeechPriority)
        -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let languages = options.languages.map(SupportedLanguages.base)
                if priority == .dictation, case .nemotron(let engine)? = try? await self.engine(for: languages, priority: priority) {
                    do {
                        try await self.live(audio, on: engine, options: options, continuation: continuation)
                    } catch {
                        continuation.finish(throwing: error is CancellationError ? SpeechError.failed("Cancelled") : error)
                    }
                    return
                }
                let session = IncrementalSession(vad: self.makeVAD(), parameters: priority == .meeting ? .meeting : .dictation,
                                                 channel: options.channel)
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

    /// Live dictation on Nemotron (stt-second-engine.md §5.3): every clip goes straight into the model, the text so far
    /// comes back as partials (about once per 1.12 s chunk), and key-up decodes only the last chunk. Silero still decides
    /// whether anything was said, over the whole stream, as for the other engines.
    private func live(_ audio: AsyncStream<AudioClip>, on engine: NemotronEngine, options: TranscriptionOptions,
                      continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation) async throws {
        var speech = LiveSpeechTracker(vad: makeVAD())
        var origin: TimeInterval?
        var partial = ""
        try await gated { try await engine.begin() }
        for await clip in audio {
            try Task.checkCancellation()
            if origin == nil { origin = clip.startTime }
            speech.append(clip.samples)
            let text = try await gated { try await engine.append(clip.samples) }
            if !text.isEmpty, text != partial {
                partial = text
                continuation.yield(.partial(text))
            }
        }
        try Task.checkCancellation()
        let heard = try await gated { try await engine.end() }
        let regions = speech.finish()
        let speechSamples = regions.reduce(0) { $0 + $1.count }
        guard let first = regions.first, let last = regions.last,
              speechSamples >= Int(VADParameters.dictation.minimumSpeech * Double(AudioClip.sampleRate)) else { throw SpeechError.noSpeech }
        let text = TranscriptGuard.accept(heard, speechSeconds: Double(speechSamples) / Double(AudioClip.sampleRate), quiet: speech.isQuiet)
        guard !text.isEmpty else { throw SpeechError.noSpeech }
        let start = (origin ?? 0) + Double(first.lowerBound) / Double(AudioClip.sampleRate)
        let end = (origin ?? 0) + Double(last.upperBound) / Double(AudioClip.sampleRate)
        let segment = TranscriptSegment(channel: options.channel, start: start, end: end, text: text)
        continuation.yield(.segment(segment))
        continuation.yield(.final(Transcript(text: text, language: "en", segments: [segment])))
        continuation.finish()
    }

    /// One engine call behind the dictation slot of the priority gate.
    private func gated<T>(_ work: () async throws -> T) async throws -> T {
        await gate.acquire(.dictation)
        defer { gate.release() }
        return try await work()
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
    private let channel: AudioChannel
    private(set) var segments: [TranscriptSegment] = []
    private var confidences: [Double] = []
    var language: (String, Double)?

    init(vad: SpeechProbabilityModel, parameters: VADParameters, channel: AudioChannel = .mic) {
        self.vad = vad
        self.channel = channel
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
        segments.append(TranscriptSegment(channel: channel, start: time(of: region.lowerBound), end: time(of: region.upperBound), text: transcript.text))
        confidences.append(transcript.confidence)
    }
}

/// Speech regions and loudness of a live stream, scored window by window so nothing but the open window is kept.
struct LiveSpeechTracker {
    private let vad: SpeechProbabilityModel
    private var segmenter: StreamingSegmenter
    private var pending: [Float] = []
    private var scored = 0
    private var regions: [Range<Int>] = []
    private var energy: Double = 0
    private var voicedSamples = 0

    init(vad: SpeechProbabilityModel) {
        self.vad = vad
        segmenter = StreamingSegmenter(window: vad.window, parameters: .dictation)
    }

    mutating func append(_ samples: [Float]) {
        pending += samples
        let whole = pending.count / vad.window * vad.window
        guard whole > 0 else { return }
        score(Array(pending[..<whole]))
        pending.removeFirst(whole)
    }

    /// Closes the stream; returns the speech regions in stream samples.
    mutating func finish() -> [Range<Int>] {
        let total = scored + pending.count
        if !pending.isEmpty { score(pending + [Float](repeating: 0, count: vad.window - pending.count)) }
        pending = []
        if let open = segmenter.finish(totalSamples: total) { regions.append(open) }
        return regions
    }

    /// The speech is under −45 dBFS on average (the phantom-text check, `TranscriptGuard.isQuiet`).
    var isQuiet: Bool { voicedSamples == 0 || 10 * log10(energy / Double(voicedSamples) + 1e-12) < -45 }

    private mutating func score(_ samples: [Float]) {
        let probabilities = vad.probabilities(samples, continuing: scored > 0)
        for (k, p) in probabilities.enumerated() where p >= VADParameters.dictation.releaseThreshold {
            for sample in samples[k * vad.window..<min(samples.count, (k + 1) * vad.window)] { energy += Double(sample * sample) }
            voicedSamples += vad.window
        }
        regions += segmenter.push(probabilities)
        scored += samples.count
    }
}

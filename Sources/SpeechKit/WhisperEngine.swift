import Foundation
import SuperFlowCore
import whisper

/// A whisper.cpp context (local-models.md §2.1): weights loaded once, Metal on, flash attention on, warmed with a
/// silent decode so the first dictation does not pay for pipeline compilation. Calls are serialised by the actor.
public actor WhisperEngine {
    public let modelURL: URL
    private var context: OpaquePointer?

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    /// The ggml system report ("Metal = 1 | …"); proves the framework linked and initialised.
    public static var systemInfo: String { String(cString: whisper_print_system_info()) }

    /// Threads for decoding: most performance cores, leaving room for the UI and the capture threads.
    static let threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))

    /// whisper.cpp reports every load and every VAD call on stderr; keep warnings and errors, in the unified log.
    static let quietLogs: Void = {
        whisper_log_set({ level, text, _ in
            guard level.rawValue >= GGML_LOG_LEVEL_WARN.rawValue, let text else { return }
            Log.speech.error("whisper: \(String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)")
        }, nil)
    }()

    public func load(useGPU: Bool = true) throws {
        WhisperEngine.quietLogs
        var params = whisper_context_default_params()
        params.use_gpu = useGPU
        params.flash_attn = true
        guard let context = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw SpeechError.failed("Couldn't load \(modelURL.lastPathComponent)")
        }
        self.context = context
    }

    /// One second of silence through the full pipeline (§4 "Warm Metal pipelines").
    public func warm() {
        _ = try? transcribe(AudioClip(samples: [Float](repeating: 0, count: AudioClip.sampleRate)), language: isMultilingual ? "en" : nil,
                            prompt: nil)
    }

    public var isLoaded: Bool { context != nil }
    public var isMultilingual: Bool { context.map { whisper_is_multilingual($0) != 0 } ?? false }

    /// Spoken-language identification on the first ≤ 10 s (§2.10): the most likely of `candidates` (all 99 when empty)
    /// and its probability among all languages, so a language outside the selection shows up as low confidence.
    public func detectLanguage(_ clip: AudioClip, among candidates: [String]) throws -> (language: String, probability: Double) {
        guard let context else { throw SpeechError.engineUnavailable("Whisper isn't loaded.") }
        guard isMultilingual else { return ("en", 1) }
        let head = Array(clip.samples.prefix(10 * AudioClip.sampleRate))
        let status = head.withUnsafeBufferPointer { whisper_pcm_to_mel(context, $0.baseAddress, Int32($0.count), WhisperEngine.threads) }
        guard status == 0 else { throw SpeechError.failed("whisper_pcm_to_mel returned \(status)") }
        var probabilities = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let top = whisper_lang_auto_detect(context, 0, WhisperEngine.threads, &probabilities)
        guard top >= 0 else { throw SpeechError.failed("Language detection failed") }
        let allowed = Set(candidates.map(SpeechLanguages.base))
        var best = (language: String(cString: whisper_lang_str(top)), probability: Double(probabilities[Int(top)]))
        if !allowed.isEmpty {
            best = ("", -1)
            for id in 0...Int(whisper_lang_max_id()) {
                let code = String(cString: whisper_lang_str(Int32(id)))
                if allowed.contains(code), Double(probabilities[id]) > best.probability { best = (code, Double(probabilities[id])) }
            }
            if best.probability < 0 { best = (candidates[0], 0) }
        }
        return best
    }

    /// Greedy decode of one clip with the hallucination thresholds of §2.12. `audio_ctx` is sized to the clip (4× faster
    /// on short utterances) unless `fullWindow`; `language` nil lets Whisper detect it.
    public func transcribe(_ clip: AudioClip, language: String?, prompt: String?, fullWindow: Bool = false) throws -> Transcript {
        guard let context else { throw SpeechError.engineUnavailable("Whisper isn't loaded.") }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = WhisperEngine.threads
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.no_speech_thold = 0.6
        params.logprob_thold = -1.0
        params.entropy_thold = 2.4
        params.temperature_inc = 0          // no temperature fallback on the hot path
        params.single_segment = false
        params.no_context = true
        params.detect_language = false
        params.carry_initial_prompt = prompt != nil
        params.audio_ctx = fullWindow ? 0 : WhisperEngine.audioContext(for: clip.duration)
        let languageC: UnsafeMutablePointer<CChar>? = strdup(language ?? (isMultilingual ? "auto" : "en"))
        let promptC: UnsafeMutablePointer<CChar>? = prompt.flatMap { strdup($0) }
        defer { free(languageC); free(promptC) }
        params.language = languageC.map { UnsafePointer($0) }
        params.initial_prompt = promptC.map { UnsafePointer($0) }
        let status = clip.samples.withUnsafeBufferPointer { whisper_full(context, params, $0.baseAddress, Int32($0.count)) }
        guard status == 0 else { throw SpeechError.failed("whisper_full returned \(status)") }
        let count = whisper_full_n_segments(context)
        var segments: [TranscriptSegment] = []
        var logProbability = 0.0, tokens = 0
        for i in 0..<count {
            let text = String(cString: whisper_full_get_segment_text(context, i)).trimmingCharacters(in: .whitespaces)
            for t in 0..<whisper_full_n_tokens(context, i) {
                let p = Double(whisper_full_get_token_p(context, i, t))
                if p > 0 { logProbability += log(p); tokens += 1 }
            }
            guard !text.isEmpty else { continue }
            segments.append(TranscriptSegment(start: clip.startTime + Double(whisper_full_get_segment_t0(context, i)) / 100,
                                              end: clip.startTime + Double(whisper_full_get_segment_t1(context, i)) / 100, text: text))
        }
        let detected = String(cString: whisper_lang_str(whisper_full_lang_id(context)))
        let confidence = tokens > 0 ? exp(logProbability / Double(tokens)) : 0
        return Transcript(text: segments.map(\.text).joined(separator: " "), language: language ?? detected, confidence: confidence,
                          segments: segments)
    }

    /// `(seconds + 1) / 30 × 1500 + 64`, at least 256 and at most the full 1500 (§2.1 finding 1).
    static func audioContext(for seconds: TimeInterval) -> Int32 {
        Int32(max(256, min(1500, Int((seconds + 1) / 30 * 1500) + 64)))
    }

    public func unload() {
        if let context { whisper_free(context) }
        context = nil
    }

    deinit { if let context { whisper_free(context) } }
}

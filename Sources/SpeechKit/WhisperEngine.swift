import Foundation
import SuperFlowCore
import whisper

/// A whisper.cpp context (local-models.md §2.1): weights loaded once, Metal on, flash attention on. Each stream gets
/// its own `whisper_state` later (`whisper_full_with_state`); this wrapper covers loading and one-shot decoding.
public actor WhisperEngine {
    public let modelURL: URL
    private var context: OpaquePointer?

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    /// The ggml system report ("Metal = 1 | …"); proves the framework linked and initialised.
    public static var systemInfo: String { String(cString: whisper_print_system_info()) }

    public func load(useGPU: Bool = true) throws {
        var params = whisper_context_default_params()
        params.use_gpu = useGPU
        params.flash_attn = true
        guard let context = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw SpeechError.failed("Couldn't load \(modelURL.lastPathComponent)")
        }
        self.context = context
    }

    public var isLoaded: Bool { context != nil }
    public var isMultilingual: Bool { context.map { whisper_is_multilingual($0) != 0 } ?? false }

    /// Greedy decode of one clip with the hallucination guards' thresholds (local-models.md §2.12).
    public func transcribe(_ clip: AudioClip, language: String?, prompt: String?, threads: Int32 = 4) throws -> Transcript {
        guard let context else { throw SpeechError.engineUnavailable("Whisper isn't loaded.") }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = threads
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.no_speech_thold = 0.6
        params.logprob_thold = -1.0
        params.entropy_thold = 2.4
        params.single_segment = false
        params.detect_language = false
        let seconds = clip.duration
        params.audio_ctx = Int32(max(256, min(1500, Int((seconds + 1) / 30 * 1500) + 64)))
        let languageC: UnsafeMutablePointer<CChar>? = language.flatMap { strdup($0) }
        let promptC: UnsafeMutablePointer<CChar>? = prompt.flatMap { strdup($0) }
        defer { free(languageC); free(promptC) }
        params.language = languageC.map { UnsafePointer($0) }
        params.initial_prompt = promptC.map { UnsafePointer($0) }
        let status = clip.samples.withUnsafeBufferPointer { whisper_full(context, params, $0.baseAddress, Int32($0.count)) }
        guard status == 0 else { throw SpeechError.failed("whisper_full returned \(status)") }
        let count = whisper_full_n_segments(context)
        var segments: [TranscriptSegment] = []
        for i in 0..<count {
            let text = String(cString: whisper_full_get_segment_text(context, i)).trimmingCharacters(in: .whitespaces)
            segments.append(TranscriptSegment(start: Double(whisper_full_get_segment_t0(context, i)) / 100,
                                              end: Double(whisper_full_get_segment_t1(context, i)) / 100, text: text))
        }
        let detected = String(cString: whisper_lang_str(whisper_full_lang_id(context)))
        return Transcript(text: segments.map(\.text).joined(separator: " "), language: language ?? detected, segments: segments)
    }

    public func unload() {
        if let context { whisper_free(context) }
        context = nil
    }

    deinit { if let context { whisper_free(context) } }
}

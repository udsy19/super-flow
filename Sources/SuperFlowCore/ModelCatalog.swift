import Foundation

/// The compiled-in model catalog (local-models.md §5.2, §9.1). SHA-256 values are the Hugging Face LFS ids, verified by
/// downloading and hashing. Single files pin their bytes by hash; Core ML folders pin the repository commit
/// (`revision`), so a re-upload can never change what is installed.
public enum ModelCatalog {
    static let gib: Int64 = 1 << 30

    private static func hf(_ repo: String, _ revision: String, _ file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")!
    }

    // MARK: ASR

    /// Default dictation ASR on Apple silicon: 25 European languages, ANE, precompiled Core ML.
    public static let parakeetV3 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v3", kind: .asr, name: "Parakeet TDT 0.6B v3", engine: "fluidaudio",
        bytes: 470 * 1_000_000, repository: "FluidInference/parakeet-tdt-0.6b-v3-coreml", revision: "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe",
        licence: "CC-BY-4.0",
        attribution: "NVIDIA Parakeet TDT 0.6B v3, CC-BY-4.0; Core ML conversion by Fluid Inference (modified).",
        languages: ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro",
                    "sk", "sl", "es", "sv", "ru", "uk"],
        minRAM: 1 * gib)

    /// Live English dictation (stt-second-engine.md): cache-aware streaming RNNT on the ANE, text every 1.12 s while the
    /// key is held, so key-up only finishes the last chunk. Opt-in from Settings › Models; in no preset.
    public static let nemotronStreamingEN = ModelDescriptor(
        id: "nemotron-speech-streaming-en-0.6b-1120ms", kind: .asr, name: "Nemotron Speech Streaming 0.6B (English)",
        engine: "fluidaudio-nemotron", bytes: 626_803_815, repository: "FluidInference/nemotron-speech-streaming-en-0.6b-coreml",
        revision: "e673531caa6d25ab7baf5a8c14c9b99ba1551838", subfolder: "nemotron_coreml_1120ms", licence: "NVIDIA Open Model License",
        attribution: "NVIDIA Nemotron Speech Streaming EN 0.6B. Licensed by NVIDIA Corporation under the NVIDIA Open Model License; "
            + "Core ML conversion by Fluid Inference (modified).",
        languages: ["en"], minRAM: 1 * gib)

    /// Apple's SpeechAnalyzer on macOS 26: nothing for Super Flow to download (the OS manages the model), 30 locales of
    /// 10 languages, one at a time, no detection (stt-second-engine.md §6). Offered only on macOS 26.
    public static let appleSpeech = ModelDescriptor(
        id: "apple-speech-transcriber", kind: .asr, name: "Apple on-device (macOS 26)", engine: "apple", bytes: 0,
        licence: "Part of macOS", attribution: "Apple SpeechAnalyzer and SpeechTranscriber, part of macOS 26.",
        languages: ["en", "de", "es", "fr", "it", "ja", "ko", "pt", "yue", "zh"])

    /// Multilingual fallback (99 languages) and the Intel engine; downloaded on demand.
    public static let whisperLargeV3Turbo = ModelDescriptor(
        id: "ggml-large-v3-turbo-q5_0", kind: .asr, name: "Whisper large-v3-turbo (q5_0)", engine: "whisper",
        bytes: 574_041_195, url: hf("ggerganov/whisper.cpp", "main", "ggml-large-v3-turbo-q5_0.bin"),
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", licence: "MIT",
        attribution: "OpenAI Whisper large-v3-turbo weights (MIT), ggml conversion by the whisper.cpp project.", minRAM: 1 * gib)

    public static let whisperSmall = ModelDescriptor(
        id: "ggml-small-q5_1", kind: .asr, name: "Whisper small (q5_1)", engine: "whisper",
        bytes: 190_085_487, url: hf("ggerganov/whisper.cpp", "main", "ggml-small-q5_1.bin"),
        sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb", licence: "MIT",
        attribution: "OpenAI Whisper small weights (MIT), ggml conversion by the whisper.cpp project.", minRAM: 512 * 1_048_576)

    /// The bootstrap model: 60 MB, multilingual, downloaded during onboarding so "try it" always works.
    public static let whisperBase = ModelDescriptor(
        id: "ggml-base-q5_1", kind: .asr, name: "Whisper base (q5_1)", engine: "whisper",
        bytes: 59_707_625, url: hf("ggerganov/whisper.cpp", "main", "ggml-base-q5_1.bin"),
        sha256: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898", licence: "MIT",
        attribution: "OpenAI Whisper base weights (MIT), ggml conversion by the whisper.cpp project.", minRAM: 256 * 1_048_576)

    // MARK: VAD

    /// Silero VAD, bundled with the app (0.9 MB); the whisper.cpp ggml export used on Intel.
    public static let sileroVAD = ModelDescriptor(
        id: "ggml-silero-v6.2.0", kind: .vad, name: "Silero VAD v6.2.0", engine: "whisper",
        bytes: 885_098, url: hf("ggml-org/whisper-vad", "main", "ggml-silero-v6.2.0.bin"),
        sha256: "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987", licence: "MIT",
        attribution: "Silero VAD (MIT), ggml conversion by the whisper.cpp project.", minRAM: 16 * 1_048_576)

    // MARK: LLM

    /// Default cleanup model (standard preset).
    public static let qwen35_2B = ModelDescriptor(
        id: "Qwen3.5-2B-Q4_K_M", kind: .llm, name: "Qwen3.5 2B (Q4_K_M)", engine: "llama",
        bytes: 1_280_835_840, url: hf("unsloth/Qwen3.5-2B-GGUF", "main", "Qwen3.5-2B-Q4_K_M.gguf"),
        sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223", licence: "Apache-2.0",
        attribution: "Qwen3.5-2B by the Qwen team (Apache-2.0), GGUF quantisation by Unsloth.", minRAM: 2 * gib)

    /// Light cleanup model for 8 GB Macs and Intel background notes.
    public static let qwen35_0_8B = ModelDescriptor(
        id: "Qwen3.5-0.8B-Q4_K_M", kind: .llm, name: "Qwen3.5 0.8B (Q4_K_M)", engine: "llama",
        bytes: 532_517_120, url: hf("unsloth/Qwen3.5-0.8B-GGUF", "main", "Qwen3.5-0.8B-Q4_K_M.gguf"),
        sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517", licence: "Apache-2.0",
        attribution: "Qwen3.5-0.8B by the Qwen team (Apache-2.0), GGUF quantisation by Unsloth.", minRAM: 1 * gib)

    /// Transforms, Command Mode and meeting notes.
    public static let qwen35_4B = ModelDescriptor(
        id: "Qwen3.5-4B-Q4_K_M", kind: .llm, name: "Qwen3.5 4B (Q4_K_M)", engine: "llama",
        bytes: 2_740_937_888, url: hf("unsloth/Qwen3.5-4B-GGUF", "main", "Qwen3.5-4B-Q4_K_M.gguf"),
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4", licence: "Apache-2.0",
        attribution: "Qwen3.5-4B by the Qwen team (Apache-2.0), GGUF quantisation by Unsloth.", minRAM: 4 * gib)

    /// Alternative notes model (the A/B candidate).
    public static let qwen3_4BInstruct = ModelDescriptor(
        id: "Qwen3-4B-Instruct-2507-Q4_K_M", kind: .llm, name: "Qwen3 4B Instruct 2507 (Q4_K_M)", engine: "llama",
        bytes: 2_497_281_120, url: hf("unsloth/Qwen3-4B-Instruct-2507-GGUF", "main", "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"),
        sha256: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597", licence: "Apache-2.0",
        attribution: "Qwen3-4B-Instruct-2507 by the Qwen team (Apache-2.0), GGUF quantisation by Unsloth.", minRAM: 6 * gib)

    // MARK: Meetings pack

    public static let diarization = ModelDescriptor(
        id: "speaker-diarization-community-1", kind: .diarization, name: "Speaker diarization (Community-1)", engine: "fluidaudio",
        bytes: 22 * 1_000_000, repository: "FluidInference/speaker-diarization-coreml", revision: "7eab74f3463c736418d0eb10296261ae581146c9",
        licence: "CC-BY-4.0",
        attribution: "pyannote Community-1 segmentation, WeSpeaker ResNet34-LM embedding and BUT Speech@FIT PLDA (CC-BY-4.0); "
            + "Core ML conversions by Fluid Inference (modified).", minRAM: 256 * 1_048_576)

    public static let localVQE = ModelDescriptor(
        id: "localvqe-1.3", kind: .echoCancel, name: "LocalVQE 1.3 (echo removal)", engine: "fluidaudio",
        bytes: 19_600_000, repository: "FluidInference/localvqe-coreml", revision: "4205430781c240397073d6f7bf676fb4c732fc12",
        licence: "Apache-2.0",
        attribution: "LocalVQE by Fluid Inference (Apache-2.0).", minRAM: 128 * 1_048_576)

    public static let all: [ModelDescriptor] = [
        parakeetV3, nemotronStreamingEN, appleSpeech, whisperLargeV3Turbo, whisperSmall, whisperBase, sileroVAD, qwen35_2B, qwen35_0_8B,
        qwen35_4B, qwen3_4BInstruct, diarization, localVQE,
    ]

    public static func descriptor(_ id: String) -> ModelDescriptor? { all.first { $0.id == id } }

    /// The dictation engines Settings › Models offers on this Mac: Parakeet (the default) and the live English Nemotron on
    /// Apple silicon, Apple's own on macOS 26; Intel Macs run Whisper and have no choice to make.
    public static func dictationEngines(isAppleSilicon: Bool, hasAppleSpeech: Bool) -> [ModelDescriptor] {
        guard isAppleSilicon else { return [] }
        return [parakeetV3, nemotronStreamingEN] + (hasAppleSpeech ? [appleSpeech] : [])
    }

    /// The cleanup models Settings › Models offers (cleanup-quality.md §7): Qwen3.5-2B, the default everywhere, and the
    /// 4B "best quality" model on Macs with 24 GB or more, where it is already downloaded for meeting notes.
    public static func cleanupModels(isAppleSilicon: Bool, memoryBytes: Int64) -> [ModelDescriptor] {
        isAppleSilicon && memoryBytes >= 24 * gib ? [qwen35_2B, qwen35_4B] : []
    }

    /// The models the dictation and meetings presets install (local-models.md §9.2).
    public struct Preset: Equatable, Sendable {
        public var name: String
        public var dictation: [ModelDescriptor]
        public var meetings: [ModelDescriptor]
        public var dictationBytes: Int64 { dictation.reduce(0) { $0 + $1.bytes } }
        public var meetingsBytes: Int64 { meetings.reduce(0) { $0 + $1.bytes } }
    }

    /// Chooses by architecture and memory (bandwidth classes are approximated by memory, local-models.md §9.2).
    public static func preset(isAppleSilicon: Bool, memoryBytes: Int64) -> Preset {
        let gb = Double(memoryBytes) / Double(gib)
        if !isAppleSilicon {
            return Preset(name: "Intel", dictation: [gb <= 8 ? whisperBase : whisperSmall, whisperBase].uniqued(),
                          meetings: [qwen35_0_8B, diarization])
        }
        if gb < 12 {
            return Preset(name: "Apple silicon, light", dictation: [parakeetV3, whisperBase, qwen35_0_8B],
                          meetings: [diarization, localVQE, qwen35_2B])
        }
        return Preset(name: gb >= 24 ? "Apple silicon, 32 GB+" : "Apple silicon, standard",
                      dictation: [parakeetV3, whisperBase, qwen35_2B], meetings: [diarization, localVQE, qwen35_4B])
    }
}

private extension Array where Element == ModelDescriptor {
    func uniqued() -> [ModelDescriptor] {
        var seen: Set<String> = []
        return filter { seen.insert($0.id).inserted }
    }
}

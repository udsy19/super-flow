import Foundation
import FluidAudio
import SpeechKit
import CleanupKit
import SuperFlowCore

// Smoke checks that every native dependency links and initialises. Real models are used only when present in the
// folders `SUPERFLOW_DEV_MODELS` names (colon-separated), or in the installed Models folder; they are never in the repo.
func registerNativeSmokeTests() {
    SelfTest.cases.append(("Native.whisperLinks", { nativeWhisper() }))
    SelfTest.cases.append(("Native.llamaLinks", { nativeLlama() }))
    SelfTest.cases.append(("Native.fluidAudioLoads", { nativeFluidAudio() }))
    SelfTest.cases.append(("Native.llamaLoadsModel", { MainActor.assumeIsolated { nativeLlamaModel() } }))
    SelfTest.cases.append(("Native.parakeetLoadsModel", { MainActor.assumeIsolated { nativeParakeetModel() } }))
}

/// Folders a developer may point the smoke tests at: `SUPERFLOW_DEV_MODELS` (colon-separated), else the real
/// `Application Support/Super Flow/Models/<kind>` folders (read only; the self-test's own paths stay temporary).
private var devModelFolders: [URL] {
    if let env = ProcessInfo.processInfo.environment["SUPERFLOW_DEV_MODELS"] {
        return env.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(SuperFlowPaths.supportFolderName + "/Models", isDirectory: true)
    return ModelKind.allCases.map { support.appendingPathComponent($0.rawValue, isDirectory: true) }
}

private func find(_ name: String) -> URL? {
    devModelFolders.map { $0.appendingPathComponent(name) }.first { FileManager.default.fileExists(atPath: $0.path) }
}

private func nativeWhisper() {
    let info = WhisperEngine.systemInfo
    check(!info.isEmpty, "whisper_print_system_info returns a report")
    print("  whisper: \(info.prefix(120))")
    let missing = WhisperEngine(modelURL: URL(fileURLWithPath: "/nonexistent/ggml.bin"))
    let result = MainActor.assumeIsolated { complete(30) { try await missing.load() } }
    if case .failure(let error)? = result { check(error is SpeechError, "a missing whisper model fails cleanly") }
    else { check(false, "loading a missing whisper model must throw") }
}

private func nativeLlama() {
    _ = LlamaEngine.backendReady
    check(Machine.isAppleSilicon == LlamaEngine.supportsGPUOffload || !Machine.isAppleSilicon, "llama backend initialised; GPU offload \(LlamaEngine.supportsGPUOffload)")
    let missing = LlamaEngine(modelURL: URL(fileURLWithPath: "/nonexistent/model.gguf"))
    let result = MainActor.assumeIsolated { complete(30) { try await missing.load() } }
    if case .failure(let error)? = result { check(error is SpeechError, "a missing GGUF fails cleanly") }
    else { check(false, "loading a missing GGUF must throw") }
}

private func nativeFluidAudio() {
    // Types resolve and the default configurations build: the package linked, including its C and binary targets.
    let config = ASRConfig.default
    check(config.sampleRate == 16_000, "FluidAudio ASRConfig at 16 kHz")
    check(VadManager.sampleRate == 16_000 && VadManager.chunkSize > 0, "FluidAudio VAD constants")
    check(!AsrModels.modelsExist(at: URL(fileURLWithPath: "/nonexistent"), version: .v3), "modelsExist on a missing folder is false")
    _ = TdtDecoderState.make()
}

@MainActor private func nativeLlamaModel() {
    guard let gguf = find("Qwen3.5-4B-Q4_K_M.gguf") ?? find(ModelCatalog.qwen35_2B.fileName) ?? find(ModelCatalog.qwen35_0_8B.fileName) else {
        print("  (skipped: no GGUF in the dev model folders)"); return
    }
    let engine = LlamaEngine(modelURL: gguf)
    let started = Date()
    switch complete(300, { try await engine.load(contextSize: 2048) }) {
    case .success?:
        let loaded = Date().timeIntervalSince(started)
        let tokens = complete { await engine.tokenize("Clean up dictated text.") }
        let context = complete { await engine.contextSize }
        let vocab = complete { await engine.vocabularySize }
        if case .success(let tokens)? = tokens, case .success(let context)? = context, case .success(let vocab)? = vocab {
            check(!tokens.isEmpty && context == 2048 && vocab > 1000, "GGUF loaded: context \(context), vocab \(vocab), \(tokens.count) tokens")
            print("  llama: \(gguf.lastPathComponent) loaded in \(String(format: "%.2f", loaded)) s, \(tokens.count) tokens, vocab \(vocab)")
        } else { check(false, "engine queries complete") }
        _ = complete { await engine.unload() }
    case .failure(let error)?: check(false, "GGUF load failed: \(error.localizedDescription)")
    case nil: check(false, "GGUF load timed out")
    }
}

@MainActor private func nativeParakeetModel() {
    guard Machine.isAppleSilicon, let folder = find("parakeet-tdt-0.6b-v3"), ParakeetEngine.modelsExist(at: folder) else {
        print("  (skipped: no Parakeet v3 Core ML folder in the dev model folders)"); return
    }
    let engine = ParakeetEngine(directory: folder)
    let started = Date()
    switch complete(600, { try await engine.load() }) {
    case .success?:
        print("  parakeet: loaded in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        // One second of silence: the engine must run end to end and return (near-)empty text, not throw.
        let silence = AudioClip(samples: [Float](repeating: 0, count: AudioClip.sampleRate))
        switch complete(120, { try await engine.transcribe(silence) }) {
        case .success(let transcript)?:
            check(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20, "silence transcribes to (near) nothing: '\(transcript.text)'")
        case .failure(let error)?: check(false, "transcribe failed: \(error.localizedDescription)")
        case nil: check(false, "transcribe timed out")
        }
        _ = complete { await engine.unload() }
    case .failure(let error)?: check(false, "Parakeet load failed: \(error.localizedDescription)")
    case nil: check(false, "Parakeet load timed out")
    }
}

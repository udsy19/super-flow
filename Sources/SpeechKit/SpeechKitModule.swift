import Combine
import Foundation
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum SpeechKitModule {
    @MainActor public static func install() {
        Services.models = ModelManager.shared
        Services.speech = SpeechService.shared
    }
}

/// Placeholder model manager (local-models.md §5): reports what is on disk under `SuperFlowPaths.models`; downloads,
/// resume and import are the module's next step.
@MainActor
final class ModelManager: ModelManaging {
    static let shared = ModelManager()
    private let changeSubject = PassthroughSubject<String, Never>()

    var catalog: [ModelDescriptor] { ModelCatalog.all }

    func state(of id: String) -> ModelState { location(of: id) == nil ? .notDownloaded : .installed }

    func location(of id: String) -> URL? {
        guard let model = ModelCatalog.descriptor(id) else { return nil }
        let url = SuperFlowPaths.models(model.kind).appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func download(_ id: String) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ModelCatalog.descriptor(id) == nil ? ModelError.unknownModel(id)
                                : SpeechError.engineUnavailable("Model downloads aren't available yet."))
        }
    }

    func pause(_ id: String) {}

    func delete(_ id: String) throws {
        guard let url = location(of: id) else { throw ModelError.unknownModel(id) }
        try FileManager.default.removeItem(at: url)
        changeSubject.send(id)
    }

    func importModel(_ id: String, from file: URL) async throws {
        throw SpeechError.engineUnavailable("Model import isn't available yet.")
    }

    var diskUsage: Int64 {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: SuperFlowPaths.models, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }

    var changes: AnyPublisher<String, Never> { changeSubject.eraseToAnyPublisher() }

    // The automatic queue (AutoDownloadPolicy) is the module's next step; until then it reports why it is idle.
    private(set) var autoDownloadStatus: AutoDownloadStatus = .idle

    func startAutomaticDownloads() {
        autoDownloadStatus = Defaults[.autoDownloadModels] ? .idle : .disabled
    }

    func setUserBusy(_ busy: Bool) {}

    func readiness(of id: String) -> Double? { nil }
}

/// Placeholder speech service: owns the engines, hands dictation priority over meetings. Transcription returns
/// `engineUnavailable` until an engine is prepared.
@MainActor
final class SpeechService: SpeechRecognizing {
    static let shared = SpeechService()
    private var parakeet: ParakeetEngine?
    private var whisper: WhisperEngine?
    private(set) var activeEngineID: String?

    var availableEngines: [String] {
        ModelCatalog.all.filter { $0.kind == .asr && Services.models.state(of: $0.id) == .installed }.map(\.id)
    }

    func prepare(modelID: String) async throws {
        guard let model = ModelCatalog.descriptor(modelID), let url = Services.models.location(of: modelID) else {
            throw SpeechError.modelNotInstalled(modelID)
        }
        switch model.engine {
        case "fluidaudio":
            let engine = ParakeetEngine(directory: url)
            try await engine.load()
            parakeet = engine
        case "whisper":
            let engine = WhisperEngine(modelURL: url)
            try await engine.load()
            whisper = engine
        default:
            throw SpeechError.engineUnavailable("Unknown engine \(model.engine)")
        }
        activeEngineID = modelID
        Log.speech.info("Prepared \(modelID, privacy: .public)")
    }

    func unload() {
        let parakeet = parakeet, whisper = whisper
        self.parakeet = nil
        self.whisper = nil
        activeEngineID = nil
        Task { await parakeet?.unload(); await whisper?.unload() }
    }

    func transcribe(_ audio: AudioClip, options: TranscriptionOptions, priority: SpeechPriority) async throws -> Transcript {
        if let parakeet { return try await parakeet.transcribe(audio) }
        if let whisper {
            let language = options.languages.count == 1 ? options.languages[0] : nil
            let prompt = options.vocabulary.isEmpty ? nil : "Vocabulary: " + options.vocabulary.prefix(50).joined(separator: ", ") + "."
            return try await whisper.transcribe(audio, language: language, prompt: prompt)
        }
        throw SpeechError.engineUnavailable("No speech engine is loaded.")
    }

    func transcribeIncrementally(_ audio: AsyncStream<AudioClip>, options: TranscriptionOptions, priority: SpeechPriority)
        -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var samples: [Float] = []
                for await clip in audio { samples += clip.samples }
                do {
                    let transcript = try await self.transcribe(AudioClip(samples: samples), options: options, priority: priority)
                    continuation.yield(.final(transcript))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func speechSegments(in audio: AudioClip) async -> [Range<Int>] {
        audio.samples.isEmpty ? [] : [0..<audio.samples.count]
    }

    func diarize(_ audio: AudioClip) async throws -> [TranscriptSegment] {
        throw SpeechError.engineUnavailable("Diarization isn't available yet.")
    }
}

import Foundation
import FluidAudio
import SuperFlowCore

/// Parakeet TDT via FluidAudio (local-models.md §2.3): precompiled Core ML on the ANE, loaded from the app's own
/// `Models/asr/<id>` folder rather than FluidAudio's cache.
public actor ParakeetEngine {
    public let directory: URL
    private var manager: AsrManager?

    public init(directory: URL) {
        self.directory = directory
    }

    /// Whether every `.mlmodelc` component and the vocabulary are in `directory`.
    public static func modelsExist(at directory: URL) -> Bool {
        AsrModels.modelsExist(at: directory, version: .v3)
    }

    public func load() async throws {
        let models = try AsrModels.loadLocal(from: directory, version: .v3)
        let manager = AsrManager(config: .default, models: models)
        try await manager.loadModels(models)
        self.manager = manager
    }

    public var isLoaded: Bool { manager != nil }

    public func transcribe(_ clip: AudioClip) async throws -> Transcript {
        guard let manager else { throw SpeechError.engineUnavailable("Parakeet isn't loaded.") }
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(clip.samples, decoderState: &state)
        return Transcript(text: result.text, confidence: Double(result.confidence))
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
    }
}

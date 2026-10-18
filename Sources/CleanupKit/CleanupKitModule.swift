import Foundation
import SuperFlowCore

/// Registers this module's service in `Services` (called once at launch).
public enum CleanupKitModule {
    @MainActor public static func install() {
        Services.cleanup = TextCleaner.shared
    }
}

/// Placeholder for the cleanup pipeline (behaviour.md §8, local-models.md §3): rules around an optional local LLM.
/// Until the module is built out it passes the transcript through with the `clientDisabled` skip reason, so the app
/// links, runs and inserts raw text.
@MainActor
final class TextCleaner: TextCleaning {
    static let shared = TextCleaner()
    private var engine: LlamaEngine?

    var isModelReady: Bool { engine != nil }

    func prepare(modelID: String) async throws {
        guard let url = Services.models.location(of: modelID) else { throw SpeechError.modelNotInstalled(modelID) }
        let engine = LlamaEngine(modelURL: url)
        try await engine.load()
        self.engine = engine
        Log.cleanup.info("Loaded \(modelID, privacy: .public)")
    }

    func unload() {
        let engine = engine
        self.engine = nil
        Task { await engine?.unload() }
    }

    func warm(style: WritingStyle, level: CleanupLevel, category: AppCategory) async {}

    func clean(_ input: CleanupInput, budget: TimeInterval) async -> CleanupOutput {
        CleanupOutput(text: input.transcript.text, skipReason: .clientDisabled)
    }

    func transform(_ text: String, instruction: String) async throws -> String {
        throw SpeechError.engineUnavailable("Transforms aren't available yet.")
    }
}

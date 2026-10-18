import FluidAudio
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum SpeechKitModule {
    @MainActor public static func install() {
        // Every model arrives through `ModelManager` (guards, resume, SHA-256); FluidAudio must never fetch on its own.
        ModelHub.offlineMode = true
        Services.models = ModelManager.shared
        Services.speech = SpeechService.shared
    }
}

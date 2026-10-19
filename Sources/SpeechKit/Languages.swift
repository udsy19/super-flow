import Foundation
import SuperFlowCore

/// How the language settings reach the engines (behaviour.md §8.7, local-models.md §2.10); the lists and the engine
/// coverage are `SupportedLanguages` in Core.
public enum SpeechLanguages {
    /// The languages a transcription should consider: empty for auto-detect (everything the engine knows).
    public static func requested(selected: [String], autoDetect: Bool) -> [String] {
        guard !autoDetect else { return [] }
        var seen: Set<String> = []
        return selected.map(SupportedLanguages.base).filter { seen.insert($0).inserted }
    }
}

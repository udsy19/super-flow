import Foundation
import SuperFlowCore

/// Dictation languages (behaviour.md §8.7, local-models.md §2.10): which engine covers them and how they reach the engines.
public enum SpeechLanguages {
    /// Parakeet TDT v3's 25 languages.
    public static let parakeet: Set<String> = Set(ModelCatalog.parakeetV3.languages)

    /// "en-US" → "en", "pt_BR" → "pt".
    public static func base(_ code: String) -> String {
        String(code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(code)).lowercased()
    }

    /// The languages a transcription should consider: empty for auto-detect (everything the engine knows).
    public static func requested(selected: [String], autoDetect: Bool) -> [String] {
        guard !autoDetect else { return [] }
        var seen: Set<String> = []
        return selected.map(base).filter { seen.insert($0).inserted }
    }

    /// Whether Parakeet can serve these languages: a non-empty list it fully covers. Empty means auto-detect among
    /// Whisper's 99, which Parakeet cannot do.
    public static func parakeetCovers(_ languages: [String]) -> Bool {
        !languages.isEmpty && languages.allSatisfy { parakeet.contains(base($0)) }
    }
}

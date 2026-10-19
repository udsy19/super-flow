import Foundation

/// The dictation languages (behaviour.md §8.7, local-models.md §2.10) as BCP-47 base codes: Parakeet's 25 come from
/// its catalog entry; Whisper's are the list whisper.cpp ships (99 plus Cantonese). The hub offers the union; the speech service picks
/// the engine that covers the selection.
public enum SupportedLanguages {
    public static let parakeet: [String] = ModelCatalog.parakeetV3.languages

    public static let whisper: [String] = [
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo", "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es", "et",
        "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw", "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja", "jw", "ka",
        "kk", "km", "kn", "ko", "la", "lb", "ln", "lo", "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl",
        "nn", "no", "oc", "pa", "pl", "ps", "pt", "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq", "sr", "su", "sv", "sw",
        "ta", "te", "tg", "th", "tk", "tl", "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh",
    ]

    /// Every language some engine knows, sorted by their display names in the current locale.
    public static var all: [String] {
        Array(Set(parakeet + whisper)).sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }

    /// "en-US" → "en", "pt_BR" → "pt".
    public static func base(_ code: String) -> String {
        String(code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(code)).lowercased()
    }

    /// "English", "Portuguese"; the code upper-cased when the locale has no name for it.
    public static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code.uppercased()
    }

    /// Whether Parakeet can serve these languages: a non-empty list it fully covers. Empty means auto-detect among
    /// Whisper's 99, which Parakeet cannot do.
    public static func parakeetCovers(_ languages: [String]) -> Bool {
        !languages.isEmpty && languages.allSatisfy { parakeet.contains(base($0)) }
    }
}

import Foundation

/// Locales Nemotron 3.5 has a language prompt for (from the GGUF's `asr.rnnt.prompt_dictionary`).
public enum Languages {
    public static let auto = "auto"

    public static let codes = [
        "en-US", "en-GB", "es-ES", "es-US", "fr-FR", "fr-CA", "de-DE", "it-IT", "pt-PT", "pt-BR",
        "nl-NL", "ro-RO", "pl-PL", "cs-CZ", "sk-SK", "hu-HU", "el-GR", "bg-BG", "hr-HR", "sl-SI",
        "sv-SE", "da-DK", "no-NO", "fi-FI", "et-EE", "lv-LV", "lt-LT", "uk-UA", "ru-RU", "tr-TR",
        "mt-MT", "ar-AR", "he-IL", "fa-IR", "hi-IN", "bn-IN", "ur-PK", "ta-IN", "te-IN", "mr-IN",
        "zh-CN", "zh-TW", "ja-JP", "ko-KR", "th-TH", "vi-VN", "id-ID", "ms-MY",
    ]

    public static func displayName(_ code: String, locale: Locale = .current) -> String {
        if code == auto { return "Auto-detect" }
        return locale.localizedString(forIdentifier: code) ?? code
    }
}

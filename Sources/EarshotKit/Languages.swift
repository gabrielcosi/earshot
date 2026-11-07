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

    /// The code the Spoken menu offers for a language the engine reported: the same locale, or
    /// the first with its language. Nil when the menu offers none.
    public static func code(for reported: String) -> String? {
        codes.contains(reported) ? reported : codes.first { language($0) == language(reported) }
    }

    /// A locale code's language, without its region: "fr" for "fr-CA".
    static func language(_ code: String) -> String {
        Locale.Language(identifier: code).languageCode?.identifier ?? code
    }

    /// A language's name without its region: "French" for "fr-CA".
    public static func name(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: language(code)) ?? code
    }

    /// The spoken languages, short enough for the menu bar's menu at any choice: names without
    /// their region, unless several share a name ("English (US, GB)"). Past two names, or past one
    /// that needs its regions, the first and a count, as the menu counts apps.
    public static func summary(_ codes: [String], locale: Locale = .current) -> String {
        guard !codes.isEmpty else { return "Any language" }
        var regions: [(name: String, regions: [String])] = []
        for code in codes {
            let name = name(code, locale: locale)
            let region = Locale.Language(identifier: code).region?.identifier ?? ""
            if let index = regions.firstIndex(where: { $0.name == name }) {
                regions[index].regions.append(region)
            } else {
                regions.append((name, [region]))
            }
        }
        let labels = regions.map { group in
            group.regions.count > 1
                ? "\(group.name) (\(group.regions.joined(separator: ", ")))" : group.name
        }
        let short =
            labels.count == 1 || labels.count == 2 && regions.allSatisfy { $0.regions.count == 1 }
        return short ? labels.joined(separator: ", ") : "\(labels[0]) + \(labels.count - 1)"
    }

    public static func displayName(_ code: String, locale: Locale = .current) -> String {
        if code == auto { return "Auto-detect" }
        return locale.localizedString(forIdentifier: code) ?? code
    }
}

import Foundation

/// The captions overlay's title, from the language settings: a session's source language is not
/// tracked, and detecting it per line would flicker as speakers switch.
public enum CaptionsTitle {
    /// `spoken` holds locale codes, empty for any language; `target` is the language translated
    /// into. Nil when nothing is translated: translation is off, or only the target language is
    /// spoken. Speech in the target language is never translated, so it names no pair.
    public static func text(
        spoken: [String], target: String, translating: Bool, locale: Locale = .current
    ) -> String? {
        guard translating else { return nil }
        let into = language(target)
        let from = Set(spoken.map(language)).subtracting([into])
        if !spoken.isEmpty, from.isEmpty { return nil }
        if from.count == 1, let source = from.first {
            return "\(name(source, locale)) → \(name(into, locale))"
        }
        return "Translating into \(name(into, locale))"
    }

    private static func language(_ code: String) -> String {
        Locale.Language(identifier: code).languageCode?.identifier ?? code
    }

    private static func name(_ language: String, _ locale: Locale) -> String {
        locale.localizedString(forLanguageCode: language) ?? language
    }
}

/// The captions overlay's text sizes: steps of the transcript's own, which are Dynamic Type body
/// sizes. Small is the transcript's default size; Medium and Large are the approved design's.
public enum CaptionTextSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var points: Double {
        switch self {
        case .small: 17
        case .medium: 23
        case .large: 28
        }
    }
}

/// Where the captions overlay opens: where it was left, unless that is on no screen any more.
public enum CaptionsPlacement {
    /// `screens` are the screens' visible frames, the main screen first. A frame off every screen,
    /// saved on a display that is gone, would open where nobody can see or reach it; the overlay
    /// then opens at the bottom centre of the main screen, raised by its own height, clear of the
    /// controls a full-screen call keeps along the bottom.
    public static func frame(saved: CGRect?, screens: [CGRect], size: CGSize) -> CGRect {
        if let saved, screens.contains(where: { $0.intersects(saved) }) { return saved }
        guard let main = screens.first else { return CGRect(origin: .zero, size: size) }
        return CGRect(
            x: (main.midX - size.width / 2).rounded(), y: main.minY + size.height,
            width: size.width, height: size.height)
    }
}

/// Whether a line is still waiting for its translation, so that showing translations alone shows
/// nothing for it yet.
public enum TranslationWait {
    /// A finished line waits until its translation lands or the translator settles it otherwise.
    public static func pending(translation: String?, settled: Bool) -> Bool {
        translation == nil && !settled
    }

    /// Words still being recognized are translated as they grow, without an outcome to record,
    /// so the translator's own rule decides: words in the target language are never translated,
    /// nor those in a language in `unavailable`, whose pair needs a download or is unsupported.
    /// Words too few to tell the language are the original, and wait.
    public static func pending(
        live text: String, translation: String?, into target: String, unavailable: [String] = []
    ) -> Bool {
        guard translation == nil else { return false }
        guard let source = LanguageDetection.dominant(text) else { return true }
        let same = { (code: String) in
            LanguageDetection.sameLanguage(source, Locale.Language(identifier: code))
        }
        return !same(target) && !unavailable.contains(where: same)
    }
}

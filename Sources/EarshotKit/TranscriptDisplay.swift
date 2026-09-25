import Foundation

/// Which text of a translated line the window shows.
public enum TranslationDisplay: String, CaseIterable, Sendable {
    case original
    case both
    case translation

    /// The text in the line's main style, and the translation under it in "both". A line with no
    /// translation, because it is already in the target language, shows its original everywhere.
    public func text(original: String, translation: String?) -> (main: String, under: String?) {
        switch self {
        case .original: (original, nil)
        case .both: (original, translation)
        case .translation: (translation ?? original, nil)
        }
    }
}

/// The transcript's text size in points, changed with ⌘+ and ⌘−. The steps are the body sizes
/// of Apple's Dynamic Type, from xSmall (14) through Large (17, the default) to the largest
/// accessibility size (53), with the macOS body size (13) below them.
public enum TranscriptTextSize {
    public static let standard = 17.0
    static let steps: [Double] = [13, 14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]

    public static func larger(than size: Double) -> Double {
        steps.first { $0 > size } ?? steps[steps.count - 1]
    }

    public static func smaller(than size: Double) -> Double {
        steps.last { $0 < size } ?? steps[0]
    }

    public static func clamped(_ size: Double) -> Double {
        steps.min { abs($0 - size) < abs($1 - size) } ?? standard
    }
}

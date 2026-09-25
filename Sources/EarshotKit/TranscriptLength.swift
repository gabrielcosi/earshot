import Foundation

/// How long a transcript runs, the same in the sidebar and the header.
public enum TranscriptLength {
    /// The session in memory knows where its last line ends.
    public static func of(_ transcript: Transcript) -> Double? { transcript.utterances.last?.end }

    /// A saved file keeps only where each line starts, so it runs to its last line's start.
    public static func of(_ document: TranscriptDocument) -> Double? { document.lines.last?.start }

    /// Whole minutes, and at least one, so no transcript reads as empty.
    public static func text(_ seconds: Double, locale: Locale = .current) -> String {
        Duration.seconds(max(seconds, 60)).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }
}

import Foundation

/// Where the player is in a transcript's kept audio, and how that reads: the waveform's seek
/// mapping, the line being played, and the time shown and spoken.
public enum Playback {
    public static func time(atFraction fraction: Double, of duration: Double) -> Double {
        min(max(fraction, 0), 1) * duration
    }

    public static func fraction(of time: Double, in duration: Double) -> Double {
        duration > 0 ? min(max(time / duration, 0), 1) : 0
    }

    /// The last line to start at or before `time`; nil before the first one starts.
    public static func line(at time: Double, starts: [Double]) -> Int? {
        starts.lastIndex { $0 <= time }
    }

    /// When the line being played next changes: where the next line starts, or the end.
    public static func nextChange(after time: Double, starts: [Double], duration: Double)
        -> Double
    {
        starts.first { $0 > time } ?? duration
    }

    /// Within this long of a line's start, stepping back goes to the line before rather than
    /// the start of this one: the window Music's Previous uses before it goes to the song
    /// before, so stepping back while playing does not keep landing on the same line.
    private static let restartWindow = 3.0

    /// A line forward: the next line's start, or the end. A line back: the start of the line
    /// `time` is in, or of the one before when `time` is within `restartWindow` of its start.
    public static func step(from time: Double, forward: Bool, starts: [Double], duration: Double)
        -> Double
    {
        if forward { return nextChange(after: time, starts: starts, duration: duration) }
        guard let current = starts.last(where: { $0 <= time }) else { return 0 }
        if time - current >= restartWindow { return current }
        return starts.last { $0 < current } ?? 0
    }

    /// "00:05 / 32:14"; with hours on both sides once the audio runs an hour.
    public static func clock(_ time: Double, of duration: Double) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern =
            duration >= 3600 ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)
        func text(_ seconds: Double) -> String {
            Duration.seconds(Int(max(seconds, 0))).formatted(.time(pattern: pattern))
        }
        return "\(text(min(time, duration))) / \(text(duration))"
    }

    /// "1 minute, 5 seconds of 32 minutes, 14 seconds": VoiceOver reads "01:05" as a time of day.
    public static func spoken(_ time: Double, of duration: Double, locale: Locale = .current)
        -> String
    {
        func words(_ seconds: Double) -> String {
            Duration.seconds(Int(seconds)).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale))
        }
        return "\(words(min(time, duration))) of \(words(duration))"
    }
}

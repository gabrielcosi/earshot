import Foundation

public enum MarkdownExport {
    public static func render(
        _ transcript: Transcript, startedAt: Date, names: [Speaker: String] = [:],
        rules: WordRules? = nil
    ) -> String {
        var lines = ["# \(title(for: startedAt))", ""]
        for utterance in transcript.utterances {
            let name = names[utterance.speaker] ?? utterance.speaker.label
            let text = rules?.apply(utterance.text) ?? utterance.text
            lines.append("**\(name)** [\(timestamp(utterance.start, hundredths: true))]: \(text)")
            if let translation = utterance.currentTranslation {
                lines.append("> \(translation)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Whole seconds to read; the file keeps hundredths, because a line's time is also where its
    /// audio starts, and a whole second holds the previous speaker's last words. The engine times
    /// words on 80 ms frames, which hundredths write exactly.
    public static func timestamp(_ seconds: Double, hundredths: Bool = false) -> String {
        let centiseconds = max(0, Int((seconds * 100).rounded()))
        let total = hundredths ? centiseconds / 100 : max(0, Int(seconds.rounded(.down)))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        let fraction = hundredths ? String(format: ".%02d", centiseconds % 100) : ""
        return hours > 0
            ? String(format: "%d:%02d:%02d%@", hours, minutes, secs, fraction)
            : String(format: "%02d:%02d%@", minutes, secs, fraction)
    }

    /// The title a transcript gets when it is written.
    public static func title(for date: Date) -> String {
        "Transcript \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Whether `title` is still the one Earshot wrote, judged against the start time the file's
    /// name records rather than by how the title reads.
    public static func hasDefaultTitle(_ title: String, filename: String) -> Bool {
        date(fromFilename: filename).map { title == self.title(for: $0) } ?? false
    }

    public static func filename(for date: Date) -> String {
        "\(filenameFormatter.string(from: date)) transcript.md"
    }

    /// When the session in a file named by `filename(for:)` started, to the minute.
    public static func date(fromFilename name: String) -> Date? {
        guard name.hasSuffix(" transcript.md") else { return nil }
        return filenameFormatter.date(from: String(name.dropLast(" transcript.md".count)))
    }

    private static var filenameFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }
}

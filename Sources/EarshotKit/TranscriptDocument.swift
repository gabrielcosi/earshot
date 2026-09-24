import Foundation

/// A saved transcript's Markdown: the title, an optional summary, and the timestamped lines.
/// The summary sits above the transcript under its own heading, separated by a rule, so reading
/// the file shows where the model's text ends and the record of what was said begins.
public struct TranscriptDocument: Sendable, Equatable {
    public struct Line: Sendable, Equatable, Identifiable {
        public let label: String
        /// Seconds into the session.
        public let start: Double
        public let text: String
        public let translation: String?
        public var id: String { "\(label)@\(start)@\(text.prefix(24))" }
    }

    public struct Summary: Sendable, Equatable {
        public let text: String
        public let model: String

        public init(text: String, model: String) {
            self.text = text
            self.model = model
        }
    }

    public let title: String
    public let summary: Summary?
    public let lines: [Line]

    public init(markdown: String) {
        var title = ""
        var lines: [Line] = []
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if title.isEmpty, raw.hasPrefix("# ") {
                title = String(raw.dropFirst(2))
            } else if let match = raw.firstMatch(of: Self.lineRegex) {
                let start = match.output.2.split(separator: ":").compactMap { Double($0) }
                    .reduce(0) { $0 * 60 + $1 }
                lines.append(
                    Line(
                        label: String(match.output.1), start: start, text: String(match.output.3),
                        translation: nil))
            } else if raw.hasPrefix("> "), let last = lines.popLast() {
                lines.append(
                    Line(
                        label: last.label, start: last.start, text: last.text,
                        translation: String(raw.dropFirst(2))))
            }
        }
        self.title = title
        self.lines = lines
        summary = Self.summaryRange(in: markdown).flatMap { range in
            let body = markdown[range]
            guard let credit = body.firstMatch(of: Self.creditRegex) else { return nil }
            let text = body[credit.range.upperBound...].trimmingCharacters(
                in: .whitespacesAndNewlines)
            return Summary(text: text, model: String(credit.output.1))
        }
    }

    /// The lines as plain "Label: text", which is what a summarizer reads.
    public var transcriptText: String {
        lines.map { "\($0.label): \($0.text)" }.joined(separator: "\n")
    }

    /// Puts `summary` above the transcript, replacing an earlier one.
    public static func withSummary(_ summary: String, by model: String, in markdown: String)
        -> String
    {
        var body = markdown
        if let range = summaryRange(in: markdown), let end = markdown.range(of: transcriptHeading) {
            body.removeSubrange(range.lowerBound..<end.upperBound)
        }
        let section = """
            \(summaryHeading)

            _Summary written by \(model). Check it against the transcript below._

            \(summary.trimmingCharacters(in: .whitespacesAndNewlines))

            ---

            \(transcriptHeading)
            """
        guard let titleEnd = body.range(of: "\n\n") else { return section + "\n\n" + body }
        var result = body
        result.replaceSubrange(titleEnd, with: "\n\n" + section + "\n\n")
        return result
    }

    static let summaryHeading = "## Summary"
    static let transcriptHeading = "## Transcript"

    private static func summaryRange(in markdown: String) -> Range<String.Index>? {
        guard let start = markdown.range(of: summaryHeading),
            let end = markdown.range(of: "\n---\n", range: start.upperBound..<markdown.endIndex)
        else { return nil }
        return start.lowerBound..<end.lowerBound
    }

    /// `**Label** [mm:ss]: text`, as MarkdownExport writes it; older files have no fraction.
    nonisolated(unsafe) static let lineRegex = /^\*\*(.+?)\*\* \[([0-9:.]+)\]: (.*)$/
    nonisolated(unsafe) private static let creditRegex =
        /_Summary written by (.+?)\. Check it[^_]*_/
}

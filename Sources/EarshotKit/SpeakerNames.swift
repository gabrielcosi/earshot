import Foundation

/// Speakers in a saved Markdown transcript, and renaming them in place.
public enum SpeakerNames {
    public struct Speaker: Sendable, Equatable, Identifiable {
        public let label: String
        /// The speaker's longest lines, for recognising who they are.
        public let samples: [Sample]
        public var id: String { label }
    }

    public struct Sample: Sendable, Equatable, Hashable {
        public let text: String
        /// Seconds into the session, from the line's timestamp.
        public let start: Double
        /// Where the next line starts, so a clip stops before whoever speaks next; nil after the
        /// last line.
        public let end: Double?
    }

    /// "Me" is the microphone, already known; only remote speakers need names. Speech no speaker
    /// was found for cannot be named after one person.
    public static func speakers(in markdown: String, samples count: Int = 3) -> [Speaker] {
        var order: [String] = []
        var lines: [String: [Sample]] = [:]
        let document = TranscriptDocument(markdown: markdown).lines
        let unnamed: Set = [EarshotKit.Speaker.me.label, EarshotKit.Speaker.unknown.label]
        for (index, line) in document.enumerated() where !unnamed.contains(line.label) {
            if lines[line.label] == nil { order.append(line.label) }
            let next = document.indices.contains(index + 1) ? document[index + 1].start : nil
            lines[line.label, default: []].append(
                Sample(text: line.text, start: line.start, end: next))
        }
        return order.map { label in
            let all = lines[label] ?? []
            let longest = Set(
                all.indices.sorted { all[$0].text.count > all[$1].text.count }.prefix(count))
            return Speaker(
                label: label, samples: all.indices.filter(longest.contains).map { all[$0] })
        }
    }

    /// Renames transcript lines, and the label wherever the summary mentions it as a whole word.
    public static func rename(in markdown: String, _ names: [String: String]) -> String {
        let document = TranscriptDocument(markdown: markdown)
        var result = renameLines(in: markdown, names)
        if let summary = document.summary {
            var text = summary.text
            for (label, name) in names {
                let name = name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let pattern =
                    "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: label)
                    + "(?![\\p{L}\\p{N}])"
                text = text.replacingOccurrences(
                    of: pattern, with: NSRegularExpression.escapedTemplate(for: name),
                    options: .regularExpression)
            }
            result = TranscriptDocument.withSummary(text, by: summary.model, in: result)
        }
        return result
    }

    private static func renameLines(in markdown: String, _ names: [String: String]) -> String {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let match = line.firstMatch(of: TranscriptDocument.lineRegex),
                let name = names[String(match.output.1)]?.trimmingCharacters(in: .whitespaces),
                !name.isEmpty
            else { return String(line) }
            return "**\(name)**" + line[match.output.1.endIndex...].dropFirst(2)
        }.joined(separator: "\n")
    }

    /// The transcript line that says `name`, to show where a suggestion came from. The model's
    /// own evidence is a paraphrase, not a quote.
    public static func evidence(for name: String, in markdown: String) -> String? {
        markdown.split(separator: "\n").lazy.compactMap { line in
            line.firstMatch(of: TranscriptDocument.lineRegex).map { String($0.output.3) }
        }.first { $0.localizedCaseInsensitiveContains(name) }
    }
}

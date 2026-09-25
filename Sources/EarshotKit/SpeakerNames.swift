import Foundation

/// Naming a transcript's speakers: who there is to name, and the names in the summary's text.
public enum SpeakerNames {
    public struct Speaker: Sendable, Equatable, Identifiable {
        public let speaker: EarshotKit.Speaker
        /// What the speaker is called now.
        public let label: String
        /// The speaker's longest lines, for recognising who they are.
        public let samples: [Sample]
        public var id: EarshotKit.Speaker { speaker }
    }

    public struct Sample: Sendable, Equatable, Hashable {
        public let text: String
        /// Seconds into the session, from the line's timestamp.
        public let start: Double
        /// Where the next line starts, so a clip stops before whoever speaks next; nil after the
        /// last line.
        public let end: Double?
    }

    /// Writes `names` over their labels wherever `text` mentions a label as a whole word, as a
    /// summary does.
    public static func renameMentions(in text: String, _ names: [String: String]) -> String {
        var text = text
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
        return text
    }

    /// The transcript line that says `name`, to show where a suggestion came from. The model's
    /// own evidence is a paraphrase, not a quote.
    public static func evidence(for name: String, in markdown: String) -> String? {
        markdown.split(separator: "\n").lazy.compactMap { line in
            line.firstMatch(of: TranscriptDocument.lineRegex).map { String($0.output.3) }
        }.first { $0.localizedCaseInsensitiveContains(name) }
    }
}

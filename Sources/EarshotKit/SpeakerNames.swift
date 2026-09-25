import Foundation
import NaturalLanguage

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
            guard !name.isEmpty, let regex = wholeWord(label) else { continue }
            text = regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text),
                withTemplate: NSRegularExpression.escapedTemplate(for: name))
        }
        return text
    }

    /// Where the transcript says `name`, to show where a suggestion came from: the sentence
    /// around it, cut to `excerptLength`. Nil when no line says it as a word, or when it is a
    /// line's label, which the transcript prints but nobody said: the model sometimes answers
    /// with the label itself. The model's own evidence is not a quote.
    public static func evidence(for name: String, in markdown: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        let lines = markdown.split(separator: "\n").compactMap {
            $0.firstMatch(of: TranscriptDocument.lineRegex)?.output
        }
        guard !name.isEmpty,
            !lines.contains(where: { $0.1.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        for line in lines {
            let text = String(line.3)
            if let match = wholeWord(name, options: .caseInsensitive)?.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)),
                let range = Range(match.range, in: text)
            {
                return excerpt(of: text, around: range)
            }
        }
        return nil
    }

    /// About two lines of the naming sheet's caption: its font measures 4.6 points a character
    /// in English, and a row is about 500 points wide, which leaves room for "Suggested from".
    private static let excerptLength = 160

    private static func excerpt(of text: String, around name: Range<String.Index>) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentence = tokenizer.tokenRange(for: name)
        let trimmed = text[sentence].trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= excerptLength { return trimmed }
        // Speech recognition leaves long stretches without a full stop (a whole two-minute
        // session came back as one sentence), so keep the words either side of the name.
        let side = max(0, (excerptLength - 2 - text[name].count) / 2)
        var start =
            text.index(name.lowerBound, offsetBy: -side, limitedBy: sentence.lowerBound)
            ?? sentence.lowerBound
        var end =
            text.index(name.upperBound, offsetBy: side, limitedBy: sentence.upperBound)
            ?? sentence.upperBound
        if start > sentence.lowerBound,
            let space = text[start..<name.lowerBound].firstIndex(of: " ")
        {
            start = space
        }
        if end < sentence.upperBound, let space = text[name.upperBound..<end].lastIndex(of: " ") {
            end = space
        }
        let words = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return (start > sentence.lowerBound ? "…" : "") + words
            + (end < sentence.upperBound ? "…" : "")
    }

    /// `text` as a whole word, not inside a longer one. Unicode word boundaries find words in
    /// scripts written without spaces, such as Japanese, Chinese, and Thai.
    private static func wholeWord(
        _ text: String, options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: "\\b" + NSRegularExpression.escapedPattern(for: text) + "\\b",
            options: options.union(.useUnicodeWordBoundaries))
    }
}

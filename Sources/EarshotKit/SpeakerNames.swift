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

    /// Why a name cannot be given, as the naming panel says it.
    public enum InvalidName: Error, Equatable {
        case lineBreak
        case markdown
        case reserved(String)
        case taken(by: EarshotKit.Speaker)

        public var message: String {
            switch self {
            case .lineBreak: "A name must fit on one line."
            case .markdown: "A name can’t contain **."
            case .reserved(let name): "“\(name)” is a label Earshot uses. Choose another name."
            case .taken(let speaker): "\(speaker.label) already has this name."
            }
        }
    }

    /// The name as it is stored: trimmed, and nil for an empty one, which gives the speaker back
    /// their label. The Markdown file writes each label in bold at the start of its line and reads
    /// it back that way, so a name must not break the line or the bold, nor read as a label
    /// Earshot gives, nor as another speaker's name in `names`.
    public static func validate(
        _ name: String, for speaker: EarshotKit.Speaker, names: [EarshotKit.Speaker: String]
    ) throws(InvalidName) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if name.contains(where: \.isNewline) { throw .lineBreak }
        if name.contains("**") { throw .markdown }
        let labels = [EarshotKit.Speaker.me, .unknown, .remote(slot: 0)].map(\.label)
        if labels.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame })
            || name.wholeMatch(of: /(?i)speaker \d+/) != nil
        {
            throw .reserved(name)
        }
        if let other = names.first(where: {
            $0.key != speaker && $0.value.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            throw .taken(by: other.key)
        }
        return name
    }

    /// Writes each label's new name wherever `text` mentions the label as a whole word, as a
    /// summary does, in one pass: `names` maps every label to what it becomes, unchanged ones to
    /// themselves, so a swap or a name passed on is not renamed twice, and a label inside a longer
    /// one ("Bob" in "Bob Smith") is matched only when the longer one is not.
    public static func renameMentions(in text: String, _ names: [String: String]) -> String {
        let labels = names.keys.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard names.contains(where: { $0.key != $0.value }), !labels.isEmpty,
            let regex = wholeWord(labels)
        else { return text }
        var renamed = ""
        var rest = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let label = String(text[range])
            let name = names[label]?.trimmingCharacters(in: .whitespaces) ?? ""
            renamed += text[rest..<range.lowerBound] + (name.isEmpty ? label : name)
            rest = range.upperBound
        }
        return renamed + text[rest...]
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
            if let match = wholeWord([name], options: .caseInsensitive)?.firstMatch(
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

    /// Any of `texts` as a whole word, not inside a longer one, trying them in order. Unicode
    /// word boundaries find words in scripts written without spaces, such as Japanese, Chinese,
    /// and Thai.
    private static func wholeWord(
        _ texts: [String], options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: "\\b(?:"
                + texts.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
                + ")\\b",
            options: options.union(.useUnicodeWordBoundaries))
    }
}

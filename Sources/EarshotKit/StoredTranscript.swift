import Foundation

/// A transcript as it reads now: what was heard, with the user's edits, names, the translations
/// made from the current text, and the summary. Word rules are not in it: they apply wherever the
/// text is shown or written, so a changed rule reaches every transcript.
public struct StoredTranscript: Identifiable, Sendable, Equatable {
    public struct Paragraph: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let speaker: Speaker
        /// Seconds into the session.
        public let start: Double
        public let end: Double
        public let text: String
        /// Only a translation made from `text` as it is.
        public let translation: String?
    }

    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    /// The user's title; nil while it has Earshot's own.
    public let title: String?
    /// The kept audio's file name in the store's audio folder.
    public let audio: String?
    public let paragraphs: [Paragraph]
    /// Who spoke as it was heard, in order of first appearance, whatever edits did since.
    public let speakers: [Speaker]
    public let names: [Speaker: String]
    public let summary: TranscriptDocument.Summary?

    public func label(_ speaker: Speaker) -> String {
        names[speaker] ?? speaker.label
    }

    /// What each speaker is called now, as the summary would mention them: also those who no
    /// longer have a line, whom a summary written earlier still mentions.
    public var labels: [Speaker: String] {
        Dictionary(
            (speakers + paragraphs.map(\.speaker)).map { ($0, label($0)) },
            uniquingKeysWith: { first, _ in first })
    }

    public var length: Double? { paragraphs.map(\.end).max() }

    /// How long `speaker` talks in the lines they have now. Zero for a transcript imported from
    /// 0.1, which kept no ends.
    public func talkTime(of speaker: Speaker) -> Double {
        paragraphs.filter { $0.speaker == speaker }.reduce(0) { $0 + $1.end - $1.start }
    }

    /// The Markdown copy, in the format Earshot has always written.
    public func markdown(rules: WordRules? = nil) -> String {
        let markdown = MarkdownExport.render(
            title: title ?? MarkdownExport.title(for: startedAt),
            lines: paragraphs.map { paragraph in
                TranscriptDocument.Line(
                    label: label(paragraph.speaker), start: paragraph.start,
                    text: rules?.apply(paragraph.text) ?? paragraph.text,
                    translation: paragraph.translation)
            })
        guard let summary else { return markdown }
        return TranscriptDocument.withSummary(summary.text, by: summary.model, in: markdown)
    }

    /// The lines as plain "Label: text", which is what a summarizer reads.
    public func transcriptText(rules: WordRules? = nil) -> String {
        paragraphs.map { "\(label($0.speaker)): \(rules?.apply($0.text) ?? $0.text)" }
            .joined(separator: "\n")
    }

    /// The speakers to name: every one but the microphone, which is the user, and speech no
    /// speaker was found for. Each comes with its longest paragraphs, to recognise who it is.
    public func speakersToName(samples count: Int = 3) -> [SpeakerNames.Speaker] {
        var order: [Speaker] = []
        var samples: [Speaker: [SpeakerNames.Sample]] = [:]
        for (index, paragraph) in paragraphs.enumerated()
        where paragraph.speaker != .me && paragraph.speaker != .unknown {
            if samples[paragraph.speaker] == nil { order.append(paragraph.speaker) }
            let next = paragraphs.indices.contains(index + 1) ? paragraphs[index + 1].start : nil
            samples[paragraph.speaker, default: []].append(
                SpeakerNames.Sample(text: paragraph.text, start: paragraph.start, end: next))
        }
        return order.map { speaker in
            let all = samples[speaker] ?? []
            let longest = Set(
                all.indices.sorted { all[$0].text.count > all[$1].text.count }.prefix(count))
            return SpeakerNames.Speaker(
                speaker: speaker, label: label(speaker),
                samples: all.indices.filter(longest.contains).map { all[$0] })
        }
    }
}

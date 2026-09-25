import Foundation

/// A finished line as the transcript window shows it, built the same way from the session in
/// memory and from a saved file, so both read alike.
public struct TranscriptLine: Identifiable, Sendable, Equatable {
    /// Who spoke, as far as colour goes: the microphone, speech no speaker was found for, or the
    /// other speakers numbered in order of first appearance. The diarizer numbers speakers that
    /// way too, so a session keeps its colours when it is saved and its speakers are named.
    public enum Voice: Hashable, Sendable {
        case me
        case unknown
        case other(Int)
    }

    public let id: String
    public let speaker: String
    public let voice: Voice
    /// Seconds into the session.
    public let start: Double
    public let text: String
    public let translation: String?

    /// The short mark beside the name: a speaker's number while unnamed, else the first letter.
    public var badge: String {
        switch voice {
        case .me: return "M"
        case .unknown: return "?"
        case .other:
            if let number = speaker.firstMatch(of: /^Speaker (\d+)$/) {
                return String(number.output.1)
            }
            return speaker.first.map { String($0).uppercased() } ?? "?"
        }
    }

    /// The lines of a saved transcript. The file keeps names, not slots: "Me" is the microphone,
    /// since naming never renames it, and every other label is a speaker of its own.
    public static func lines(in document: TranscriptDocument) -> [TranscriptLine] {
        var voices = Voices<String>()
        return document.lines.enumerated().map { index, line in
            let voice: Voice =
                switch line.label {
                case Speaker.me.label: .me
                case Speaker.unknown.label: .unknown
                default: voices.voice(for: line.label)
                }
            return TranscriptLine(
                id: "\(index)", speaker: line.label, voice: voice, start: line.start,
                text: line.text, translation: line.translation)
        }
    }

    /// The finished lines of the session in memory, named and tidied as they will be saved. A
    /// paragraph shows its latest translation, which can trail the text while it grows.
    public static func lines(
        in transcript: Transcript, names: [Speaker: String] = [:], rules: WordRules? = nil
    ) -> [TranscriptLine] {
        var voices = Voices<Speaker>()
        return transcript.utterances.map { utterance in
            let voice: Voice =
                switch utterance.speaker {
                case .me: .me
                case .unknown: .unknown
                case .remote: voices.voice(for: utterance.speaker)
                }
            return TranscriptLine(
                id: utterance.id.uuidString,
                speaker: names[utterance.speaker] ?? utterance.speaker.label, voice: voice,
                start: utterance.start, text: rules?.apply(utterance.text) ?? utterance.text,
                translation: utterance.translation?.text)
        }
    }

    private struct Voices<Key: Hashable> {
        private var order: [Key: Int] = [:]

        mutating func voice(for key: Key) -> Voice {
            if let index = order[key] { return .other(index) }
            order[key] = order.count
            return .other(order.count - 1)
        }
    }
}

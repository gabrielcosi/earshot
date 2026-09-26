import Foundation

/// A finished line as the transcript window shows it, built the same way from the session in
/// memory and from a saved file, so both read alike.
public struct TranscriptLine: Identifiable, Sendable, Equatable {
    /// Who spoke, as far as colour goes: the microphone, speech no speaker was found for, or the
    /// other speakers numbered in order of first appearance. The diarizer numbers speakers that
    /// way too, so a session keeps its colours when it is stored and its speakers are named.
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

    /// The lines of a stored transcript, named, edited, and tidied as they will be exported.
    public static func lines(in stored: StoredTranscript, rules: WordRules? = nil)
        -> [TranscriptLine]
    {
        var voices = Voices()
        return stored.paragraphs.map { paragraph in
            TranscriptLine(
                id: paragraph.id.uuidString, speaker: stored.label(paragraph.speaker),
                voice: voices.voice(for: paragraph.speaker), start: paragraph.start,
                text: rules?.apply(paragraph.text) ?? paragraph.text,
                translation: paragraph.translation)
        }
    }

    /// The finished lines of the session in memory, named and tidied as they will be saved. A
    /// paragraph shows its latest translation, which can trail the text while it grows.
    public static func lines(
        in transcript: Transcript, names: [Speaker: String] = [:], rules: WordRules? = nil
    ) -> [TranscriptLine] {
        var voices = Voices()
        return transcript.utterances.map { line($0, voices: &voices, names: names, rules: rules) }
    }

    /// The session's last `count` lines, as `lines(in:names:rules:)` gives them, for the captions
    /// overlay; the rules apply to those lines alone.
    public static func latest(
        _ count: Int, in transcript: Transcript, names: [Speaker: String] = [:],
        rules: WordRules? = nil
    ) -> [TranscriptLine] {
        let utterances = transcript.utterances
        let first = max(utterances.count - count, 0)
        var voices = Voices()
        // Numbered in order of first appearance, so every earlier speaker counts.
        for utterance in utterances[..<first] { _ = voices.voice(for: utterance.speaker) }
        return utterances[first...].map { line($0, voices: &voices, names: names, rules: rules) }
    }

    private static func line(
        _ utterance: Utterance, voices: inout Voices, names: [Speaker: String], rules: WordRules?
    ) -> TranscriptLine {
        TranscriptLine(
            id: utterance.id.uuidString,
            speaker: names[utterance.speaker] ?? utterance.speaker.label,
            voice: voices.voice(for: utterance.speaker),
            start: utterance.start, text: rules?.apply(utterance.text) ?? utterance.text,
            translation: utterance.translation?.text)
    }

    /// The microphone and speech with no speaker have colours of their own; the other speakers
    /// are numbered in order of first appearance.
    private struct Voices {
        private var order: [Speaker: Int] = [:]

        mutating func voice(for speaker: Speaker) -> Voice {
            switch speaker {
            case .me: return .me
            case .unknown: return .unknown
            case .remote:
                if let index = order[speaker] { return .other(index) }
                order[speaker] = order.count
                return .other(order.count - 1)
            }
        }
    }
}

import Foundation

/// Which capture stream a transcript event came from.
public enum Channel: String, Sendable, CaseIterable {
    /// The local microphone: always the user.
    case microphone
    /// Everything the Mac plays: the other participants.
    case system
}

public enum Speaker: Hashable, Sendable {
    case me
    /// A remote participant; `slot` is the diarizer's 1-based speaker index, 0 when unknown.
    case remote(slot: Int)
    /// Remote speech that diarizing the whole recording gave to no speaker: crosstalk, or speech
    /// over music. The live pass's slot is not used for it, because the two passes number speakers
    /// independently.
    case unknown

    public var label: String {
        switch self {
        case .me: "Me"
        case .remote(let slot) where slot > 0: "Speaker \(slot)"
        case .remote: "Remote"
        case .unknown: "Unknown speaker"
        }
    }
}

/// One final's words within a paragraph, kept apart so a refinement can replace just them.
public struct Segment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let start: Double
    public let end: Double
    public var text: String
    /// Timed words, kept so speakers can be reassigned word by word after the session.
    public var words: [Word] = []
}

/// A stretch of audio one speaker holds, from diarizing the whole recording.
public struct SpeakerTurn: Sendable, Equatable, Decodable {
    public let start: Double
    public let end: Double
    /// 1-based, in order of first appearance.
    public let speaker: Int

    public init(start: Double, end: Double, speaker: Int) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

/// A speaker turn with the words heard in its audio alone, timed from the session's start.
public struct TranscribedTurn: Sendable, Equatable {
    public let turn: SpeakerTurn
    public let words: [Word]

    public init(turn: SpeakerTurn, words: [Word]) {
        self.turn = turn
        self.words = words
    }
}

/// The segments one final added, in order, for refining that final later.
public struct AppliedFinal: Sendable, Equatable {
    public let segments: [SegmentSpan]

    public var end: Double? { segments.map(\.end).max() }
}

public struct SegmentSpan: Sendable, Equatable {
    public let id: UUID
    public let start: Double
    public let end: Double
}

public struct Utterance: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let speaker: Speaker
    /// Seconds since the session started.
    public let start: Double
    public var end: Double
    public var segments: [Segment]
    public var translation: Translation?

    public var text: String {
        segments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A translation stays attached to the text it was made from; merges make it stale.
    public var currentTranslation: String? {
        translation.flatMap { $0.sourceText == text ? $0.text : nil }
    }

    public init(
        id: UUID = UUID(),
        speaker: Speaker,
        start: Double,
        end: Double,
        text: String,
        translation: Translation? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.start = start
        self.end = end
        self.segments = [Segment(id: UUID(), start: start, end: end, text: text)]
        self.translation = translation
    }
}

public struct Translation: Sendable, Equatable {
    public let sourceText: String
    public let text: String

    public init(sourceText: String, text: String) {
        self.sourceText = sourceText
        self.text = text
    }
}

/// One paragraph as displayed: final text, plus the words still being recognized when this is the
/// speaker's current turn.
public struct Row: Identifiable, Sendable, Equatable {
    public let id: String
    public let speaker: Speaker
    public let start: Double
    public let text: String
    public let pending: String?
    /// The paragraph's latest translation. While the paragraph grows it can trail the text; the
    /// next one replaces it.
    public let translation: String?
    public let pendingTranslation: String?
}

/// The session so far: final utterances in time order plus the in-flight partial of each channel.
public struct Transcript: Sendable, Equatable {
    public private(set) var utterances: [Utterance] = []
    public private(set) var partials: [Channel: String] = [:]
    private var liveTranslations: [Channel: Translation] = [:]

    public init() {}

    /// Utterances as paragraphs, with each channel's partial appended to the last row when that
    /// row is the channel's, and in a row of its own at the end otherwise.
    public var rows: [Row] {
        var rows = utterances.map {
            Row(
                id: $0.id.uuidString, speaker: $0.speaker, start: $0.start, text: $0.text,
                pending: nil, translation: $0.translation?.text, pendingTranslation: nil)
        }
        for channel in Channel.allCases {
            guard let partial = partials[channel], !partial.isEmpty else { continue }
            let live = liveTranslations[channel]?.text
            if let last = rows.last, Self.channel(of: last.speaker) == channel {
                rows[rows.count - 1] = Row(
                    id: last.id, speaker: last.speaker, start: last.start, text: last.text,
                    pending: partial, translation: last.translation, pendingTranslation: live)
            } else {
                let speaker =
                    utterances.last { Self.channel(of: $0.speaker) == channel }?.speaker
                    ?? Self.speaker(nil, channel)
                rows.append(
                    Row(
                        id: "pending-\(channel.rawValue)", speaker: speaker,
                        start: utterances.last?.end ?? 0, text: "", pending: partial,
                        translation: nil, pendingTranslation: live))
            }
        }
        return rows
    }

    public mutating func applyPartial(_ delta: String, on channel: Channel) {
        partials[channel, default: ""] += delta
    }

    /// Splits a final result into one segment per run of consecutive words from the same speaker.
    @discardableResult
    public mutating func applyFinal(transcript: String, words: [Word], on channel: Channel)
        -> AppliedFinal
    {
        partials[channel] = nil
        liveTranslations[channel] = nil
        var runs = Self.runs(words: words, channel: channel)
        if runs.isEmpty {
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return AppliedFinal(segments: []) }
            let at = utterances.last?.end ?? 0
            runs = [
                Run(speaker: Self.speaker(nil, channel), start: at, end: at, text: text, words: [])
            ]
        }
        return AppliedFinal(
            segments: runs.map { run in
                var utterance = Utterance(
                    speaker: run.speaker, start: run.start, end: run.end, text: run.text)
                utterance.segments[0].words = run.words
                insert(utterance)
                let segment = utterance.segments[0]
                return SegmentSpan(id: segment.id, start: segment.start, end: segment.end)
            })
    }

    /// Replaces a final's live text with a second pass over its audio. Each word goes to the
    /// segment nearest in time, so a final that spans two speakers keeps its speaker split.
    /// Segments that get no words keep their live text.
    public mutating func refine(_ final: AppliedFinal, with words: [Word]) {
        guard !final.segments.isEmpty, !words.isEmpty else { return }
        var assigned: [UUID: [Word]] = [:]
        for word in words {
            let middle = (word.start + word.end) / 2
            let nearest = final.segments.min { lhs, rhs in
                Self.distance(middle, lhs) < Self.distance(middle, rhs)
            }
            if let nearest { assigned[nearest.id, default: []].append(word) }
        }
        for (segment, words) in assigned {
            for index in utterances.indices {
                guard
                    let position = utterances[index].segments.firstIndex(where: { $0.id == segment }
                    )
                else { continue }
                utterances[index].segments[position].text =
                    words.map(\.word).joined(separator: " ")
                utterances[index].segments[position].words = words
            }
        }
    }

    /// Replaces the remote paragraphs with the speaker turns from diarizing the whole recording,
    /// each holding the words transcribed from its own audio. Placing the live words into turns by
    /// their times does not work at a quick turn change: the engine's word times are emission
    /// times, 0.3-0.5 s after the speech (measured on `say` voices), so a turn's last word lands
    /// in the next speaker's turn whenever the gap between them is shorter than that. A turn's own
    /// audio cannot hold another speaker's words. Live words farther than that lag from every
    /// turn are speech the diarizer did not call a turn (an intro over music, crosstalk); they
    /// stay, under an unknown speaker. The microphone's paragraphs stay as they are.
    public mutating func relabel(_ turns: [TranscribedTurn]) {
        let rebuilt =
            turns.filter { !$0.words.isEmpty }.map { turn in
                Self.utterance(
                    .remote(slot: turn.turn.speaker), start: turn.turn.start, end: turn.turn.end,
                    words: turn.words)
            } + missed(by: turns.map(\.turn))
        guard !rebuilt.isEmpty else { return }
        let kept = utterances.filter { $0.speaker == .me }
        utterances = []
        for utterance in (kept + rebuilt).sorted(by: { $0.start < $1.start }) {
            insert(utterance)
        }
    }

    /// The engine's word times trail the speech: starts by 0.2-0.7 s and ends by 0.06-0.34 s
    /// (measured on `say` voices), so a word's midpoint trails by up to about 0.5 s. A live word
    /// within that of a turn is the turn's, already transcribed from the turn's audio.
    static let wordTimeLag = 0.5

    /// Runs of live remote words that no turn accounts for, under an unknown speaker.
    private func missed(by turns: [SpeakerTurn]) -> [Utterance] {
        guard !turns.isEmpty else { return [] }
        var runs: [Run] = []
        var open = false
        for word in liveRemoteWords {
            let middle = (word.start + word.end) / 2
            let nearest = turns.min { Self.distance(middle, $0) < Self.distance(middle, $1) }
            guard let nearest, Self.distance(middle, nearest) > Self.wordTimeLag else {
                open = false
                continue
            }
            let speaker = Speaker.unknown
            if open, let last = runs.indices.last, runs[last].speaker == speaker {
                runs[last].end = word.end
                runs[last].text += " " + word.word
                runs[last].words.append(word)
            } else {
                runs.append(
                    Run(
                        speaker: speaker, start: word.start, end: word.end, text: word.word,
                        words: [word]))
                open = true
            }
        }
        return runs.map {
            Self.utterance($0.speaker, start: $0.start, end: $0.end, words: $0.words)
        }
    }

    private var liveRemoteWords: [Word] {
        utterances.flatMap { utterance -> [Word] in
            guard case .remote = utterance.speaker else { return [] }
            return utterance.segments.flatMap { segment in
                segment.words.isEmpty
                    ? [Word(word: segment.text, start: segment.start, end: segment.end)]
                    : segment.words
            }
        }.filter { !$0.word.isEmpty }.sorted { $0.start < $1.start }
    }

    private static func utterance(
        _ speaker: Speaker, start: Double, end: Double, words: [Word]
    ) -> Utterance {
        var utterance = Utterance(
            speaker: speaker, start: start, end: end,
            text: words.map(\.word).joined(separator: " "))
        utterance.segments[0].words = words
        return utterance
    }

    private static func distance(_ time: Double, _ turn: SpeakerTurn) -> Double {
        time < turn.start ? turn.start - time : max(0, time - turn.end)
    }

    private static func distance(_ time: Double, _ span: SegmentSpan) -> Double {
        time < span.start ? span.start - time : max(0, time - span.end)
    }

    /// Translations finish out of order; one made from less of the paragraph never replaces one
    /// made from more, unless a refinement has since rewritten the text the older one covered.
    public mutating func setTranslation(_ translation: Translation, for id: UUID) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        let text = utterances[index].text
        guard text.hasPrefix(translation.sourceText) else { return }
        if let current = utterances[index].translation, text.hasPrefix(current.sourceText),
            current.sourceText.count > translation.sourceText.count
        {
            return
        }
        utterances[index].translation = translation
    }

    /// Kept only while the channel's partial still starts with the text that was translated.
    public mutating func setLiveTranslation(_ translation: Translation, on channel: Channel) {
        guard let partial = partials[channel], partial.hasPrefix(translation.sourceText) else {
            return
        }
        liveTranslations[channel] = translation
    }

    /// Endpointing cuts a final after 800 ms of silence, so a slow speaker arrives in fragments.
    /// A final joins the last paragraph when that paragraph is the same speaker's: a turn lasts
    /// until someone else speaks, however long the pauses.
    private mutating func insert(_ utterance: Utterance) {
        let index = utterances.lastIndex { $0.start <= utterance.start }.map { $0 + 1 } ?? 0
        if index > 0, index == utterances.count, utterances[index - 1].speaker == utterance.speaker
        {
            utterances[index - 1].segments += utterance.segments
            utterances[index - 1].end = utterance.end
            return
        }
        utterances.insert(utterance, at: index)
    }

    private struct Run {
        let speaker: Speaker
        let start: Double
        var end: Double
        var text: String
        var words: [Word]
    }

    private static func runs(words: [Word], channel: Channel) -> [Run] {
        words.reduce(into: [Run]()) { runs, word in
            let speaker = speaker(word.speaker, channel)
            if let last = runs.indices.last, runs[last].speaker == speaker {
                runs[last].end = word.end
                runs[last].text += " " + word.word
                runs[last].words.append(word)
            } else {
                runs.append(
                    Run(
                        speaker: speaker, start: word.start, end: word.end, text: word.word,
                        words: [word]))
            }
        }
    }

    private static func channel(of speaker: Speaker) -> Channel {
        switch speaker {
        case .me: .microphone
        case .remote, .unknown: .system
        }
    }

    private static func speaker(_ slot: Int?, _ channel: Channel) -> Speaker {
        switch channel {
        case .microphone: .me
        case .system: .remote(slot: slot ?? 0)
        }
    }
}

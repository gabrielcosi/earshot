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
    /// A language outside the spoken ones that the engine heard in its audio: not translated.
    var heard: HeardOutside?
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
    /// Kept by the transcript that holds the paragraph, from its sentences' outcomes.
    public internal(set) var translation = ParagraphTranslation.untranslated
    /// The paragraph's sentences, split again whenever its text changes.
    public internal(set) var sentences: [String] = []
    /// Its sentences holding words heard outside the spoken languages: they show as said.
    var heardOutside: Set<String> = []
    /// The live translation of the words its latest final added, shown after the translated
    /// sentences until one from `carriedFrom` on, where those words start, is translated.
    var carried: String?
    var carriedFrom = 0
    /// Showing translations alone, the line has shown, and stays through a change of language.
    public internal(set) var translationShown = false

    public var text: String {
        segments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public init(
        id: UUID = UUID(),
        speaker: Speaker,
        start: Double,
        end: Double,
        text: String
    ) {
        self.id = id
        self.speaker = speaker
        self.start = start
        self.end = end
        self.segments = [Segment(id: UUID(), start: start, end: end, text: text)]
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

/// Words still being recognized on one channel, with their live translation, shown apart from
/// the finished lines until their final arrives.
public struct LiveLine: Identifiable, Sendable, Equatable {
    public let channel: Channel
    public let text: String
    public let translation: String?
    public var id: Channel { channel }
}

/// The session so far: final utterances in time order plus the in-flight partial of each channel.
public struct Transcript: Sendable, Equatable {
    public internal(set) var utterances: [Utterance] = []
    public private(set) var partials: [Channel: String] = [:]
    private var liveTranslations: [Channel: Translation] = [:]
    /// The language translated into; nil while nothing is translated.
    public internal(set) var translationTarget: String?
    /// Every sentence translated this session, by its text, so a sentence is translated once
    /// however often its paragraph changes or is rebuilt.
    var outcomes: [String: SentenceOutcome] = [:]

    public init() {}

    mutating func compose(at index: Int) {
        let utterance = utterances[index]
        let translation = ParagraphTranslation.compose(
            utterance.sentences, outcome: { outcome(of: $0, in: utterance) },
            carried: utterance.carried, from: utterance.carriedFrom, into: translationTarget)
        utterances[index].translation = translation
        if translation.started || translation.text != nil {
            utterances[index].translationShown = true
        }
    }

    /// The paragraph's text changed: its sentences are split again. Returns the first sentence
    /// that is not as it was.
    @discardableResult
    mutating func textChanged(at index: Int) -> Int {
        let before = utterances[index].sentences
        utterances[index].sentences = Sentences.split(utterances[index].text)
        utterances[index].heardOutside = Sentences.holding(
            utterances[index].segments.filter { !$0.text.isEmpty }.map {
                (text: $0.text, marked: $0.heard != nil)
            })
        compose(at: index)
        return zip(before, utterances[index].sentences).prefix { $0 == $1 }.count
    }

    mutating func composeAll() {
        for index in utterances.indices { compose(at: index) }
    }

    /// Live translations, of the words in flight and carried onto finished lines, are in the
    /// language they were made for: a new target, or translation turned off, drops them.
    public mutating func dropLiveTranslations() {
        liveTranslations = [:]
        for index in utterances.indices { utterances[index].carried = nil }
        composeAll()
    }

    /// Each channel's words in flight, the microphone first.
    public var liveLines: [LiveLine] {
        [Channel.microphone, .system].compactMap { channel in
            guard let partial = partials[channel], !partial.isEmpty else { return nil }
            return LiveLine(
                channel: channel, text: partial, translation: liveTranslations[channel]?.text)
        }
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
        let carried = liveTranslations.removeValue(forKey: channel)?.text
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
                let index = insert(utterance)
                // A final split between speakers has no one run its live translation matches.
                utterances[index].carried = runs.count == 1 ? carried : nil
                utterances[index].carriedFrom = textChanged(at: index)
                compose(at: index)
                let segment = utterance.segments[0]
                return SegmentSpan(id: segment.id, start: segment.start, end: segment.end)
            })
    }

    /// Replaces a final's live text with a second pass over its audio. Each word goes to the
    /// segment nearest in time, so a final that spans two speakers keeps its speaker split.
    /// Segments that get no words keep their live text; those that do are marked `heard`.
    public mutating func refine(_ final: AppliedFinal, with words: [Word], heard: String? = nil) {
        guard !final.segments.isEmpty, !words.isEmpty else { return }
        let heard = heard.map { HeardOutside(language: $0) }
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
                utterances[index].segments[position].heard = heard
                textChanged(at: index)
            }
        }
    }

    private static func distance(_ time: Double, _ span: SegmentSpan) -> Double {
        time < span.start ? span.start - time : max(0, time - span.end)
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
    /// Returns where the utterance went.
    @discardableResult
    mutating func insert(_ utterance: Utterance) -> Int {
        let index = utterances.lastIndex { $0.start <= utterance.start }.map { $0 + 1 } ?? 0
        if index > 0, index == utterances.count, utterances[index - 1].speaker == utterance.speaker
        {
            utterances[index - 1].segments += utterance.segments
            utterances[index - 1].end = utterance.end
            return index - 1
        }
        utterances.insert(utterance, at: index)
        return index
    }

    struct Run {
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

    private static func speaker(_ slot: Int?, _ channel: Channel) -> Speaker {
        switch channel {
        case .microphone: .me
        case .system: .remote(slot: slot ?? 0)
        }
    }
}

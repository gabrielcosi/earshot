import Foundation

extension Transcript {
    /// Replaces the remote paragraphs with the speaker turns from diarizing the whole recording,
    /// each holding the words transcribed from its own audio. Placing the live words into turns by
    /// their times does not work at a quick turn change: the engine's word times are emission
    /// times, 0.3-0.5 s after the speech (measured on `say` voices), so a turn's last word lands
    /// in the next speaker's turn whenever the gap between them is shorter than that. A turn's own
    /// audio cannot hold another speaker's words. Live words farther than that lag from every
    /// turn with words are speech the diarizer did not call a turn (an intro over music,
    /// crosstalk), or a turn whose own audio came back empty; they stay, under that turn's
    /// speaker or else an unknown one. The microphone's paragraphs stay as they are. When no
    /// turn holds words (there are none, or none had speech, as in a recording of only music),
    /// nothing changes and it returns false.
    @discardableResult
    public mutating func relabel(_ turns: [TranscribedTurn]) -> Bool {
        let heard = turns.filter { !$0.words.isEmpty }
        guard !heard.isEmpty else { return false }
        let rebuilt =
            heard.map { turn in
                Self.utterance(
                    .remote(slot: turn.turn.speaker), start: turn.turn.start, end: turn.turn.end,
                    words: turn.words, heard: turn.heard)
            }
            + missed(
                by: heard.map(\.turn), inside: turns.filter(\.words.isEmpty).map(\.turn))
        let kept = utterances.filter { $0.speaker == .me }
        utterances = []
        for utterance in (kept + rebuilt).sorted(by: { $0.start < $1.start }) {
            insert(utterance)
        }
        // Rebuilt paragraphs look their sentences up in the session's outcomes, so what was
        // translated while listening shows at once; all were on screen as they were heard.
        for index in utterances.indices {
            utterances[index].carried = nil
            utterances[index].translationShown = true
            textChanged(at: index)
        }
        return true
    }

    /// The engine's word times trail the speech: starts by 0.2-0.7 s and ends by 0.06-0.34 s
    /// (measured on `say` voices), so a word's midpoint trails by up to about 0.5 s. A live word
    /// within that of a turn is the turn's, already transcribed from the turn's audio.
    static let wordTimeLag = 0.5

    /// Measured on the code-switch truth set of `say` voices: a live word's midpoint trails the
    /// speech by 0.20 s at the median and 0.40 s at p90. Taken back by 0.3 s, live words went to
    /// another speaker's diarized turn 6 times in 3,671, against 28 untaken and 13 or 14 at 0.2
    /// and 0.4 s.
    static let wordMidpointLag = 0.3

    /// The remote words the transcript holds in each turn, to check the turn's own transcription
    /// against: each word goes to the turn nearest the time it was spoken, within the engine's
    /// lag. Placed by the time it was emitted, a turn's last word would go to the next turn when
    /// it began within the lag, and a turn kept as its reference would then hold it twice. A word
    /// more than the lag after the turn by the time it was emitted is one the turn missed, and
    /// stays out of it: it is kept on its own.
    public func remoteWords(in turns: [SpeakerTurn]) -> [[Word]] {
        var words = Array(repeating: [Word](), count: turns.count)
        for word in liveRemoteWords {
            let emitted = (word.start + word.end) / 2
            if let index = Self.turnIndex(at: emitted - Self.wordMidpointLag, in: turns),
                Self.distance(emitted, turns[index]) <= Self.wordTimeLag
            {
                words[index].append(word)
            }
        }
        return words
    }

    /// Runs of live remote words that no turn with words accounts for, under the speaker of the
    /// empty turn they fall in, or an unknown one.
    private func missed(by turns: [SpeakerTurn], inside empty: [SpeakerTurn]) -> [Utterance] {
        var runs: [Run] = []
        var open = false
        for word in liveRemoteWords {
            let middle = (word.start + word.end) / 2
            guard Self.turn(at: middle, in: turns) == nil else {
                open = false
                continue
            }
            let speaker =
                Self.turn(at: middle, in: empty).map { Speaker.remote(slot: $0.speaker) }
                ?? .unknown
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
        _ speaker: Speaker, start: Double, end: Double, words: [Word], heard: String? = nil
    ) -> Utterance {
        var utterance = Utterance(
            speaker: speaker, start: start, end: end,
            text: words.map(\.word).joined(separator: " "))
        utterance.segments[0].words = words
        utterance.segments[0].heard = heard.map { HeardOutside(language: $0) }
        return utterance
    }

    /// The turn a live word at `time` belongs to: the nearest, within the engine's lag.
    private static func turn(at time: Double, in turns: [SpeakerTurn]) -> SpeakerTurn? {
        turnIndex(at: time, in: turns).map { turns[$0] }
    }

    private static func turnIndex(at time: Double, in turns: [SpeakerTurn]) -> Int? {
        turns.indices.min { distance(time, turns[$0]) < distance(time, turns[$1]) }.flatMap {
            distance(time, turns[$0]) > wordTimeLag ? nil : $0
        }
    }

    private static func distance(_ time: Double, _ turn: SpeakerTurn) -> Double {
        time < turn.start ? turn.start - time : max(0, time - turn.end)
    }
}

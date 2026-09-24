import Foundation
import Testing

@testable import EarshotKit

@Suite struct RelabelTests {
    private func word(_ text: String, _ start: Double, speaker: Int? = nil) -> Word {
        Word(word: text, start: start, end: start + 0.3, speaker: speaker)
    }

    private func turn(_ speaker: Int, _ start: Double, _ end: Double, _ words: [Word])
        -> TranscribedTurn
    {
        TranscribedTurn(turn: SpeakerTurn(start: start, end: end, speaker: speaker), words: words)
    }

    /// The live final tags "settled." with the next speaker; the turn's own audio does not.
    @Test func eachTurnBecomesItsSpeakersParagraphFromItsOwnWords() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "",
            words: [
                word("that", 0, speaker: 2), word("is", 0.4, speaker: 2),
                word("settled.", 0.8, speaker: 1), word("Next,", 1.6, speaker: 1),
                word("budget", 2.0, speaker: 1),
            ], on: .system)
        transcript.relabel([
            turn(2, 0, 1.2, [word("that", 0), word("is", 0.4), word("settled.", 0.8)]),
            turn(1, 1.1, 2.5, [word("Next,", 1.6), word("budget", 2.0)]),
        ])
        #expect(transcript.utterances.map(\.text) == ["that is settled.", "Next, budget"])
        #expect(transcript.utterances.map(\.speaker) == [.remote(slot: 2), .remote(slot: 1)])
    }

    /// A paragraph starts where the diarizer heard the turn begin, not at its first word's time,
    /// which the engine reports 0.3-0.5 s after the speech.
    @Test func aParagraphStartsWhereItsTurnDoes() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [word("hello", 5.4, speaker: 1)], on: .system)
        transcript.relabel([turn(1, 5, 6, [word("hello", 5.4)])])
        #expect(transcript.utterances.map(\.start) == [5])
        #expect(transcript.utterances.map(\.end) == [6])
    }

    @Test func theMicrophoneKeepsItsParagraphsBetweenRelabelledOnes() {
        var transcript = Transcript()
        transcript.applyFinal(transcript: "", words: [word("hello", 0, speaker: 1)], on: .system)
        transcript.applyFinal(transcript: "", words: [word("hi", 1)], on: .microphone)
        transcript.applyFinal(transcript: "", words: [word("bye", 2, speaker: 1)], on: .system)
        transcript.relabel([
            turn(1, 0, 0.5, [word("hello", 0)]), turn(1, 2, 3, [word("bye", 2)]),
        ])
        #expect(transcript.utterances.map(\.text) == ["hello", "hi", "bye"])
        #expect(transcript.utterances.map(\.speaker) == [.remote(slot: 1), .me, .remote(slot: 1)])
    }

    /// A backchannel the diarizer heard but the recognizer found no words in adds nothing.
    @Test func aTurnWithoutWordsIsDropped() {
        var transcript = Transcript()
        transcript.applyFinal(transcript: "", words: [word("hello", 0, speaker: 1)], on: .system)
        transcript.relabel([turn(1, 0, 1, [word("hello", 0)]), turn(2, 0.8, 1.1, [])])
        #expect(transcript.utterances.map(\.speaker) == [.remote(slot: 1)])
    }

    /// An intro the diarizer heard as no turn stays, under an unknown speaker rather than a live
    /// slot, which the offline pass numbers differently; a turn's last word, which the engine
    /// times up to half a second after the turn, is not repeated.
    @Test func speechOutsideEveryTurnStaysUnderAnUnknownSpeaker() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "",
            words: [
                word("Welcome", 0, speaker: 1), word("everyone.", 0.4, speaker: 1),
                word("Right,", 3.2, speaker: 2), word("start.", 3.6, speaker: 2),
            ], on: .system)
        transcript.relabel([turn(2, 3, 3.5, [word("Right,", 3.2), word("start.", 3.6)])])
        #expect(transcript.utterances.map(\.text) == ["Welcome everyone.", "Right, start."])
        #expect(transcript.utterances.map(\.speaker) == [.unknown, .remote(slot: 2)])
    }

    @Test func noWordsInAnyTurnKeepsTheLiveTranscript() {
        var transcript = Transcript()
        transcript.applyFinal(transcript: "", words: [word("hello", 0, speaker: 1)], on: .system)
        transcript.relabel([turn(1, 0, 1, [])])
        #expect(transcript.utterances.map(\.text) == ["hello"])
    }
}

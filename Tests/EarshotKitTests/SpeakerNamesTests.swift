import Foundation
import Testing

@testable import EarshotKit

@Suite struct SpeakerNamesTests {
    private let store: TranscriptStore
    private let id = UUID()

    init() throws {
        store = try TranscriptStore.inMemory()
    }

    /// A remote speaker's line, or the microphone's without one.
    private func view(_ words: [Word]) throws -> StoredTranscript {
        var transcript = Transcript()
        for word in words {
            transcript.applyFinal(
                transcript: word.word, words: [word],
                on: word.speaker == nil ? .microphone : .system)
        }
        try store.saveLive(id, startedAt: .now, utterances: transcript.utterances)
        return try #require(try store.view(id))
    }

    @Test func listsRemoteSpeakersWithTheirLongestLinesInOrderOfAppearance() throws {
        let speakers = try view([
            Word(word: "Let's start with the thing you got wrong.", start: 3, end: 4, speaker: 1),
            Word(word: "Me?", start: 5, end: 5.5),
            Word(word: "Yes, exactly.", start: 6, end: 6.5, speaker: 2),
            Word(word: "I just want to be very clear.", start: 7, end: 8, speaker: 1),
        ]).speakersToName()
        #expect(speakers.map(\.speaker) == [.remote(slot: 1), .remote(slot: 2)])
        #expect(speakers.map(\.label) == ["Speaker 1", "Speaker 2"])
        #expect(
            speakers.first?.samples.map(\.text) == [
                "Let's start with the thing you got wrong.", "I just want to be very clear.",
            ])
        #expect(speakers.first?.samples.map(\.start) == [3, 7])
    }

    /// Speech no speaker was found for cannot be named after one person.
    @Test func anUnknownSpeakerIsNotOfferedForNaming() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Right", start: 3, end: 4, speaker: 1)],
            on: .system)
        transcript.relabel([
            TranscribedTurn(
                turn: SpeakerTurn(start: 3, end: 4, speaker: 1),
                words: [Word(word: "Right", start: 3, end: 4)])
        ])
        let unknown = Utterance(speaker: .unknown, start: 1, end: 2, text: "Welcome everyone.")
        try store.saveLive(id, startedAt: .now, utterances: [unknown] + transcript.utterances)
        let speakers = try #require(try store.view(id)).speakersToName()
        #expect(speakers.map(\.label) == ["Speaker 1"])
    }

    /// A line's time is where its clip starts, and the clip must stop where the next line begins.
    @Test func samplesKeepTheLineTimeAndEndAtTheNextLine() throws {
        let speakers = try view([
            Word(word: "yes", start: 4.6, end: 4.9, speaker: 1),
            Word(word: "no", start: 5.28, end: 5.5, speaker: 2),
        ]).speakersToName()
        #expect(speakers.first?.samples.map(\.start) == [4.6])
        #expect(speakers.first?.samples.map(\.end) == [5.28])
        #expect(speakers.last?.samples.map(\.end) == [nil])
    }

    @Test func aNamedSpeakerIsOfferedUnderTheirName() throws {
        _ = try view([Word(word: "Hello", start: 1, end: 2, speaker: 1)])
        try store.rename(id, [.remote(slot: 1): "John Doe"])
        #expect(try store.view(id)?.speakersToName().map(\.label) == ["John Doe"])
    }

    @Test func evidenceIsTheTranscriptLineThatSaysTheName() {
        let text = "**Speaker 1** [00:28]: Welcome back. I'm John Doe, and this is the show.\n"
        #expect(
            SpeakerNames.evidence(for: "John Doe", in: text)
                == "Welcome back. I'm John Doe, and this is the show.")
        #expect(SpeakerNames.evidence(for: "Jane", in: text) == nil)
    }
}

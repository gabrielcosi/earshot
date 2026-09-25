import Foundation
import Testing

@testable import EarshotKit

@Suite struct TranscriptLineTests {
    private let store: TranscriptStore
    private let id = UUID()

    init() throws {
        store = try TranscriptStore.inMemory()
    }

    private func stored(_ utterances: [Utterance]) throws -> StoredTranscript {
        try store.saveLive(id, startedAt: .now, utterances: utterances)
        try store.seal(id, at: .now)
        return try #require(try store.view(id))
    }

    /// Colours follow first appearance, so they match the live session, whose diarizer numbers
    /// speakers the same way; "Me" and speech with no speaker have colours of their own.
    @Test func voicesFollowFirstAppearance() throws {
        let lines = TranscriptLine.lines(
            in: try stored([
                Utterance(speaker: .remote(slot: 2), start: 3, end: 4, text: "a"),
                Utterance(speaker: .me, start: 5, end: 6, text: "b"),
                Utterance(speaker: .remote(slot: 1), start: 7, end: 8, text: "c"),
                Utterance(speaker: .unknown, start: 9, end: 10, text: "d"),
                Utterance(speaker: .remote(slot: 2), start: 11, end: 12, text: "e"),
            ]))
        #expect(lines.map(\.voice) == [.other(0), .me, .other(1), .unknown, .other(0)])
    }

    @Test func badgesShowTheSpeakerNumberOrTheNamesFirstLetter() throws {
        _ = try stored([
            Utterance(speaker: .remote(slot: 3), start: 1, end: 2, text: "a"),
            Utterance(speaker: .me, start: 2, end: 3, text: "b"),
            Utterance(speaker: .remote(slot: 1), start: 3, end: 4, text: "c"),
            Utterance(speaker: .unknown, start: 4, end: 5, text: "d"),
            Utterance(speaker: .remote(slot: 0), start: 5, end: 6, text: "e"),
        ])
        try store.setNames([.remote(slot: 1): "ada"], in: id)
        let lines = TranscriptLine.lines(in: try #require(try store.view(id)))
        #expect(lines.map(\.badge) == ["3", "M", "A", "?", "R"])
    }

    /// The window draws a session the same way while it is recorded and once it is stored: every
    /// line, its speaker's name and colour, its time, the tidied text, and its translation.
    @Test func aSessionReadsTheSameLiveAndStored() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "uh Hallo zusammen",
            words: [
                Word(word: "uh", start: 0.4, end: 0.5, speaker: 2),
                Word(word: "Hallo", start: 0.5, end: 0.9, speaker: 2),
                Word(word: "zusammen", start: 0.9, end: 1.3, speaker: 2),
            ], on: .system)
        transcript.applyFinal(
            transcript: "Hi", words: [Word(word: "Hi", start: 2, end: 2.2)], on: .microphone)
        transcript.applyFinal(
            transcript: "Moin", words: [Word(word: "Moin", start: 3.12, end: 3.4, speaker: 1)],
            on: .system)
        let first = transcript.utterances[0]
        transcript.setTranslation(
            Translation(sourceText: first.text, text: "Hello everyone"), for: first.id)
        let names: [Speaker: String] = [.remote(slot: 1): "Ada"]
        let rules = WordRules()

        _ = try stored(transcript.utterances)
        try store.setTranslation("Hello everyone", of: first.text, language: "en", for: first.id)
        try store.setNames(names.mapValues(Optional.some), in: id)
        let live = TranscriptLine.lines(in: transcript, names: names, rules: rules)
        let saved = TranscriptLine.lines(in: try #require(try store.view(id)), rules: rules)

        #expect(live.map(\.text) == ["Hallo zusammen", "Hi", "Moin"])
        #expect(live.map(\.speaker) == ["Speaker 2", "Me", "Ada"])
        #expect(live.map(\.voice) == [.other(0), .me, .other(1)])
        #expect(saved == live)
    }
}

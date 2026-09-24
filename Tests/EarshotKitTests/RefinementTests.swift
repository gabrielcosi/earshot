import Foundation
import Testing

@testable import EarshotKit

@Suite struct RefinementTests {
    @Test func wavHeaderDescribes16kMonoPCM16() {
        let wav = PCM.wav(Data(count: 3200))
        #expect(wav.count == 44 + 3200)
        #expect(String(bytes: wav.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(bytes: wav[8..<16], encoding: .ascii) == "WAVEfmt ")
        let rate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 16_000)
    }

    @Test func historyReturnsTheRequestedSpan() {
        var history = AudioHistory(seconds: 10)
        history.append(Data((0..<64_000).map { UInt8($0 % 256) }))
        let span = history.pcm(from: 0.5, to: 1.0)
        #expect(span?.count == 16_000)
        #expect(span?.first == UInt8(16_000 % 256))
    }

    @Test func historyForgetsAudioOlderThanItsWindow() {
        var history = AudioHistory(seconds: 1)
        history.append(Data(count: 32_000 * 3))
        #expect(history.pcm(from: 0, to: 0.5) == nil)
        #expect(history.pcm(from: 2.5, to: 3.0)?.count == 16_000)
    }

    @Test func refinementReplacesTheFinalsTextInItsParagraph() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "Hello", words: [Word(word: "Hello", start: 0, end: 1, speaker: 1)],
            on: .system)
        let final = transcript.applyFinal(
            transcript: "feeling dunk",
            words: [
                Word(word: "feeling", start: 3, end: 3.4, speaker: 1),
                Word(word: "dunk", start: 3.4, end: 3.8, speaker: 1),
            ], on: .system)
        transcript.refine(
            final,
            with: [
                Word(word: "Vielen", start: 3, end: 3.4), Word(word: "Dank.", start: 3.4, end: 3.8),
            ])
        #expect(transcript.utterances.map(\.text) == ["Hello Vielen Dank."])
    }

    @Test func refinementSplitsWordsBetweenSpeakersByTime() {
        var transcript = Transcript()
        let final = transcript.applyFinal(
            transcript: "a b",
            words: [
                Word(word: "a", start: 0, end: 1, speaker: 1),
                Word(word: "b", start: 2, end: 3, speaker: 2),
            ], on: .system)
        transcript.refine(
            final,
            with: [
                Word(word: "A1", start: 0.1, end: 0.5), Word(word: "A2", start: 0.6, end: 0.9),
                Word(word: "B1", start: 2.2, end: 2.8),
            ])
        #expect(transcript.utterances.map(\.text) == ["A1 A2", "B1"])
    }

    @Test func anEmptyRefinementKeepsTheLiveText() {
        var transcript = Transcript()
        let final = transcript.applyFinal(
            transcript: "keep", words: [Word(word: "keep", start: 0, end: 1)], on: .microphone)
        transcript.refine(final, with: [])
        #expect(transcript.utterances.map(\.text) == ["keep"])
    }
}

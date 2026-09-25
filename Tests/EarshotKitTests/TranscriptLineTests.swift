import Foundation
import Testing

@testable import EarshotKit

@Suite struct TranscriptLineTests {
    private let saved = """
        # Transcript 24. Sep 2026 at 14:18

        **Speaker 2** [00:03.25]: Let's start.
        > Fangen wir an.

        **Me** [00:05.00]: Sure.

        **Speaker 1** [00:07.00]: Hi all.

        **Unknown speaker** [00:09.00]: (music)

        **Speaker 2** [00:11.00]: Right.

        """

    @Test func savedLinesKeepEverythingTheFileHolds() {
        let lines = TranscriptLine.lines(in: TranscriptDocument(markdown: saved))
        #expect(
            lines.map(\.speaker) == [
                "Speaker 2", "Me", "Speaker 1", "Unknown speaker", "Speaker 2",
            ])
        #expect(lines.map(\.start) == [3.25, 5, 7, 9, 11])
        #expect(lines.first?.text == "Let's start.")
        #expect(lines.first?.translation == "Fangen wir an.")
        #expect(lines.dropFirst().first?.translation == nil)
    }

    /// Colours follow first appearance, so they match the live session, whose diarizer numbers
    /// speakers the same way; "Me" and speech with no speaker have colours of their own.
    @Test func voicesFollowFirstAppearance() {
        let lines = TranscriptLine.lines(in: TranscriptDocument(markdown: saved))
        #expect(lines.map(\.voice) == [.other(0), .me, .other(1), .unknown, .other(0)])
    }

    @Test func badgesShowTheSpeakerNumberOrTheNamesFirstLetter() {
        let markdown =
            "**Speaker 3** [00:01]: a\n\n**Me** [00:02]: b\n\n**ada** [00:03]: c\n\n"
            + "**Unknown speaker** [00:04]: d\n\n**Remote** [00:05]: e\n"
        let lines = TranscriptLine.lines(in: TranscriptDocument(markdown: markdown))
        #expect(lines.map(\.badge) == ["3", "M", "A", "?", "R"])
    }

    /// The window draws a session the same way before and after it is saved: every line, its
    /// speaker's name and colour, its time, the tidied text, and its translation survive the file.
    @Test func aSessionReadsTheSameLiveAndSaved() {
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

        let live = TranscriptLine.lines(in: transcript, names: names, rules: rules)
        let markdown = MarkdownExport.render(
            transcript, startedAt: .now, names: names, rules: rules)
        let reread = TranscriptLine.lines(in: TranscriptDocument(markdown: markdown))

        #expect(live.map(\.text) == ["Hallo zusammen", "Hi", "Moin"])
        #expect(live.map(\.speaker) == ["Speaker 2", "Me", "Ada"])
        #expect(live.map(\.voice) == [.other(0), .me, .other(1)])
        #expect(reread.map(\.speaker) == live.map(\.speaker))
        #expect(reread.map(\.voice) == live.map(\.voice))
        #expect(reread.map(\.start) == live.map(\.start))
        #expect(reread.map(\.text) == live.map(\.text))
        #expect(reread.map(\.translation) == live.map(\.translation))
    }
}

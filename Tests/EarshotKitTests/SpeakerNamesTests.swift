import Foundation
import Testing

@testable import EarshotKit

@Suite struct SpeakerNamesTests {
    private let markdown = """
        # Transcript 24. Sep 2026 at 14:18

        **Speaker 1** [00:03]: Let's start with the thing you got wrong.

        **Me** [00:05]: Me?

        **Speaker 2** [00:06]: Yes, exactly.
        > Ja, genau.

        **Speaker 1** [00:07]: I just want to be very clear.

        """

    @Test func listsRemoteSpeakersWithSampleLinesInOrderOfAppearance() {
        let speakers = SpeakerNames.speakers(in: markdown)
        #expect(speakers.map(\.label) == ["Speaker 1", "Speaker 2"])
        #expect(
            speakers.first?.samples.map(\.text) == [
                "Let's start with the thing you got wrong.", "I just want to be very clear.",
            ])
        #expect(speakers.first?.samples.map(\.start) == [3, 7])
    }

    /// A line's time is where its clip starts: whole seconds put the previous speaker's last
    /// words in front of it, and the clip must stop where the next line begins.
    /// Speech no speaker was found for cannot be named after one person.
    @Test func anUnknownSpeakerIsNotOfferedForNaming() {
        let markdown = """
            **Unknown speaker** [00:01]: Welcome everyone.

            **Speaker 1** [00:03]: Right, let's start.

            """
        #expect(SpeakerNames.speakers(in: markdown).map(\.label) == ["Speaker 1"])
    }

    @Test func samplesKeepTheLineTimeToTheHundredthAndEndAtTheNextLine() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [Word(word: "yes", start: 4.6, end: 4.9, speaker: 1)],
            on: .system)
        transcript.applyFinal(
            transcript: "", words: [Word(word: "no", start: 5.28, end: 5.5, speaker: 2)],
            on: .system)
        let markdown = MarkdownExport.render(transcript, startedAt: Date())
        let speakers = SpeakerNames.speakers(in: markdown)
        #expect(speakers.map(\.label) == ["Speaker 1", "Speaker 2"])
        #expect(speakers.first?.samples.map(\.start) == [4.6])
        #expect(speakers.first?.samples.map(\.end) == [5.28])
        #expect(speakers.last?.samples.map(\.end) == [nil])
    }

    @Test func renamesOnlyTheLabelAtTheStartOfEachLine() {
        let renamed = SpeakerNames.rename(in: markdown, ["Speaker 1": "John Doe"])
        #expect(renamed.contains("**John Doe** [00:03]: Let's start"))
        #expect(renamed.contains("**John Doe** [00:07]"))
        #expect(renamed.contains("**Speaker 2** [00:06]"))
        #expect(renamed.contains("**Me** [00:05]"))
    }

    @Test func evidenceIsTheTranscriptLineThatSaysTheName() {
        let text = "**Speaker 1** [00:28]: Welcome back. I'm John Doe, and this is the show.\n"
        #expect(
            SpeakerNames.evidence(for: "John Doe", in: text)
                == "Welcome back. I'm John Doe, and this is the show.")
        #expect(SpeakerNames.evidence(for: "Jane", in: text) == nil)
    }

    @Test func anEmptyNameLeavesTheLabel() {
        #expect(SpeakerNames.rename(in: markdown, ["Speaker 1": "  "]) == markdown)
    }
}

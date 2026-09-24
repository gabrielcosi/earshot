import Foundation
import Testing

@testable import EarshotKit

@Suite struct TranscriptDocumentTests {
    private let plain = """
        # Transcript 24. Sep 2026 at 14:18

        **Speaker 1** [00:03]: Let's start.

        **Me** [01:05]: Sure.
        > Klar.

        """

    @Test func parsesTitleAndTimedLines() {
        let document = TranscriptDocument(markdown: plain)
        #expect(document.title == "Transcript 24. Sep 2026 at 14:18")
        #expect(document.summary == nil)
        #expect(document.lines.map(\.label) == ["Speaker 1", "Me"])
        #expect(document.lines.map(\.start) == [3, 65])
        #expect(document.lines.last?.translation == "Klar.")
    }

    /// Files written before line times had hundredths still read.
    @Test func parsesLineTimesWithAndWithoutHundredths() {
        let document = TranscriptDocument(
            markdown: "**Speaker 1** [00:03.25]: Hi.\n\n**Me** [1:02:05]: Hello.\n")
        #expect(document.lines.map(\.start) == [3.25, 3725])
    }

    @Test func aSummaryIsAddedAboveTheTranscriptAndSeparatedFromIt() {
        let summarized = TranscriptDocument.withSummary(
            "- Agreed to ship.", by: "Apple on-device", in: plain)
        let document = TranscriptDocument(markdown: summarized)
        #expect(document.summary?.text == "- Agreed to ship.")
        #expect(document.summary?.model == "Apple on-device")
        #expect(document.lines.count == 2)
        let summaryAt = summarized.range(of: "## Summary")?.lowerBound
        let transcriptAt = summarized.range(of: "## Transcript")?.lowerBound
        #expect(summaryAt != nil && transcriptAt != nil && summaryAt! < transcriptAt!)
        #expect(summarized.contains("\n---\n"))
    }

    @Test func summarizingAgainReplacesTheSummary() {
        let once = TranscriptDocument.withSummary("first", by: "a", in: plain)
        let twice = TranscriptDocument.withSummary("second", by: "b", in: once)
        #expect(TranscriptDocument(markdown: twice).summary?.text == "second")
        #expect(twice.components(separatedBy: "## Summary").count == 2)
        #expect(TranscriptDocument(markdown: twice).lines.count == 2)
    }

    @Test func theTranscriptTextForAModelLeavesOutTranslations() {
        #expect(
            TranscriptDocument(markdown: plain).transcriptText
                == "Speaker 1: Let's start.\nMe: Sure.")
    }
}

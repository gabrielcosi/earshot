import Foundation
import Testing

@testable import EarshotKit

@Suite struct TranscriptLengthTests {
    private let english = Locale(identifier: "en_US")

    /// A session with one line said is not zero long: it runs to where that line ends.
    @Test func theSessionInMemoryRunsToTheEndOfItsLastLine() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "Hello there",
            words: [
                Word(word: "Hello", start: 0.2, end: 0.6),
                Word(word: "there", start: 0.6, end: 1.4),
            ], on: .microphone)
        #expect(TranscriptLength.of(transcript) == 1.4)
    }

    /// Under a minute reads as a minute everywhere, so no transcript looks empty.
    @Test func lengthsReadInWholeMinutes() {
        #expect(TranscriptLength.text(0, locale: english) == "1 min")
        #expect(TranscriptLength.text(1934, locale: english) == "32 min")
        #expect(TranscriptLength.text(3900, locale: english) == "1 hr, 5 min")
    }
}

@Suite struct DefaultTitleTests {
    private let started = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theTitleEarshotWroteIsTheDefault() {
        #expect(
            MarkdownExport.hasDefaultTitle(
                MarkdownExport.title(for: started), filename: MarkdownExport.filename(for: started))
        )
    }

    @Test func aTitleTheUserWroteIsNot() {
        #expect(
            !MarkdownExport.hasDefaultTitle(
                "Weekly sync", filename: MarkdownExport.filename(for: started)))
    }

    /// A title that reads like the default but names another time is the user's.
    @Test func aDefaultLookingTitleForAnotherTimeIsNot() {
        let other = started.addingTimeInterval(3600)
        #expect(
            !MarkdownExport.hasDefaultTitle(
                MarkdownExport.title(for: other), filename: MarkdownExport.filename(for: started)))
    }

    @Test func withoutAStartTimeInTheNameNothingIsTheDefault() {
        #expect(
            !MarkdownExport.hasDefaultTitle(
                MarkdownExport.title(for: started), filename: "Notes.md"))
    }
}

import Foundation
import Testing

@testable import EarshotKit

@Suite struct ProblemsTests {
    @Test func aProblemReportedAgainReplacesItsEarlierReport() {
        var problems = Problems()
        problems.report(.engineFailed("no GPU"))
        problems.report(.connectionLost(.system))
        problems.report(.engineFailed("out of memory"))
        #expect(
            problems.all == [.engineFailed("out of memory"), .connectionLost(.system)])
    }

    @Test func eachChannelAndLanguagePairHasItsOwnProblem() {
        var problems = Problems()
        problems.report(.connectionLost(.system))
        problems.report(.connectionLost(.microphone))
        problems.report(.translationNeedsDownload(from: "de", to: "en"))
        problems.report(.translationNeedsDownload(from: "fr", to: "en"))
        #expect(problems.all.count == 4)
    }

    /// A new session starts clean, but what still stands in its way stays visible.
    @Test func aNewSessionClearsOnlyTheLastSessionsProblems() {
        var problems = Problems()
        problems.report(.connectionLost(.system))
        problems.report(.engineStopped)
        problems.report(.noModel)
        problems.report(.translationNeedsDownload(from: "de", to: "en"))
        problems.startSession()
        #expect(problems.all == [.noModel, .translationNeedsDownload(from: "de", to: "en")])
    }

    @Test func resolvingRemovesTheMatchingProblems() {
        var problems = Problems()
        problems.report(.translationNeedsDownload(from: "de", to: "en"))
        problems.report(.translationUnsupported(from: "ro", to: "en"))
        problems.report(.noModel)
        problems.resolve { $0.isTranslation }
        #expect(problems.all == [.noModel])
    }

    @Test func messagesNameTheLanguagesAndTheAudio() {
        let english = Locale(identifier: "en")
        #expect(
            Problem.translationNeedsDownload(from: "de", to: "en").message(in: english)
                == "Translating German into English needs Apple's language download.")
        #expect(
            Problem.connectionLost(.microphone).message(in: english).contains(
                "your microphone"))
    }
}

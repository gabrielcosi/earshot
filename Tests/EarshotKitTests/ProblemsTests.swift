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

    /// Dismissed from the menu, a problem goes until something reports it again.
    @Test func aDismissedProblemGoesUntilItIsReportedAgain() {
        var problems = Problems()
        problems.report(.engineStopped)
        problems.report(.connectionLost(.system))
        problems.dismiss(.engineStopped)
        #expect(problems.all == [.connectionLost(.system)])
        problems.report(.engineStopped)
        #expect(problems.all == [.connectionLost(.system), .engineStopped])
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

@Suite struct SummaryFailureTests {
    @Test func networkFailuresMeanTheAddressCouldNotBeReached() {
        for code in [URLError.notConnectedToInternet, .cannotConnectToHost, .cannotFindHost] {
            #expect(SummaryFailure(URLError(code)) == .unreachable)
        }
    }

    /// A timeout comes after minutes of waiting on a server that did answer the connection.
    @Test func aTimeoutIsASlowServiceNotAnUnreachableOne() {
        #expect(SummaryFailure(URLError(.timedOut)) == .timedOut)
    }

    @Test func aRefusedKeyIsToldApartFromOtherHTTPErrors() {
        #expect(SummaryFailure(OpenAIChat.Failure.http(401, "")) == .keyRefused)
        #expect(SummaryFailure(AnthropicMessages.Failure.http(403, "")) == .keyRefused)
        #expect(SummaryFailure(OpenAIChat.Failure.http(500, "")) == .serviceError)
        #expect(SummaryFailure(AnthropicMessages.Failure.http(429, "")) == .serviceError)
    }

    @Test func otherErrorsHaveNoCause() {
        #expect(SummaryFailure(OpenAIChat.Failure.empty) == nil)
        #expect(SummaryFailure(CocoaError(.fileReadNoSuchFile)) == nil)
    }

    /// The server's own text never reaches the message.
    @Test func theMessageNamesTheCauseAndNotTheServersText() {
        let problem = Problem.summaryFailed(
            SummaryFailure(OpenAIChat.Failure.http(401, "invalid_api_key sk-123")))
        #expect(
            problem.message()
                == "Earshot could not summarize the transcript. The summary service refused the API key."
        )
        #expect(
            Problem.summaryFailed(nil).message() == "Earshot could not summarize the transcript.")
    }

    @Test func aSummaryFailureReportedAgainReplacesItsEarlierCause() {
        var problems = Problems()
        problems.report(.summaryFailed(.unreachable))
        problems.report(.summaryFailed(.keyRefused))
        #expect(problems.all == [.summaryFailed(.keyRefused)])
    }
}

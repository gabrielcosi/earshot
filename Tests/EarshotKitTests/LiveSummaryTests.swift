import Foundation
import Testing

@testable import EarshotKit

/// Summaries from real APIs. `EARSHOT_SUMMARY_KEY` plus the address and model of each format:
/// `EARSHOT_OPENAI_URL` / `EARSHOT_OPENAI_MODEL`, `EARSHOT_ANTHROPIC_URL` / `EARSHOT_ANTHROPIC_MODEL`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EARSHOT_SUMMARY_KEY"] != nil))
struct LiveSummaryTests {
    private let environment = ProcessInfo.processInfo.environment
    private let transcript = """
        Speaker 1: Let's decide the release date. I propose Friday.
        Speaker 2: Friday works. I'll update the changelog by Thursday.
        Me: Agreed, Friday it is. I'll tell the customer.
        """

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EARSHOT_OPENAI_URL"] != nil))
    func openAICompatible() async throws {
        let url = try #require(environment["EARSHOT_OPENAI_URL"].flatMap(URL.init(string:)))
        let model = try #require(environment["EARSHOT_OPENAI_MODEL"])
        let text = try await SplitSummary.summarize(transcript, language: "English") {
            try await OpenAIChat.complete(
                baseURL: url, apiKey: environment["EARSHOT_SUMMARY_KEY"], model: model, system: $0,
                user: $1)
        }
        print("openai:\n\(text)")
        #expect(text.localizedCaseInsensitiveContains("friday"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EARSHOT_ANTHROPIC_URL"] != nil))
    func anthropic() async throws {
        let url = try #require(environment["EARSHOT_ANTHROPIC_URL"].flatMap(URL.init(string:)))
        let model = try #require(environment["EARSHOT_ANTHROPIC_MODEL"])
        let text = try await SplitSummary.summarize(transcript, language: "English") {
            try await AnthropicMessages.complete(
                baseURL: url, apiKey: environment["EARSHOT_SUMMARY_KEY"], model: model,
                system: $0, user: $1)
        }
        print("anthropic:\n\(text)")
        #expect(text.localizedCaseInsensitiveContains("friday"))
    }
}

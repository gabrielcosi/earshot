import Foundation
import Testing

@testable import EarshotKit

@Suite struct SummaryTests {
    @Test func chunksSplitOnLineBoundariesWithinTheLimit() {
        let lines = (1...10).map { "Speaker 1: line number \($0) of the transcript" }
        let chunks = SummaryPrompt.chunks(of: lines.joined(separator: "\n"), limit: 100)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 100 })
        #expect(chunks.joined(separator: "\n") == lines.joined(separator: "\n"))
    }

    @Test func aTranscriptWithinTheLimitIsOneChunk() {
        #expect(SummaryPrompt.chunks(of: "Me: hi\nSpeaker 1: hello", limit: 100).count == 1)
    }

    @Test func instructionsNameTheLanguageAndTheParts() {
        let instructions = SummaryPrompt.instructions(language: "German")
        #expect(instructions.contains("German"))
        #expect(instructions.contains("Action items"))
    }

    @Test func chatRequestIsOpenAICompatible() throws {
        let request = try OpenAIChat.request(
            baseURL: try #require(URL(string: "http://localhost:4000/v1")), apiKey: "k",
            model: "m", system: "sys", user: "usr")
        #expect(request.url?.absoluteString == "http://localhost:4000/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        let body =
            try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["model"] as? String == "m")
        let messages = body?["messages"] as? [[String: String]]
        #expect(messages?.map { $0["role"] ?? "" } == ["system", "user"])
    }

    @Test func chatResponseContentIsRead() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"Notes"}}]}"#.utf8)
        #expect(try OpenAIChat.content(of: data) == "Notes")
    }

    @Test func renamingASpeakerAlsoRenamesTheSummary() {
        let markdown = TranscriptDocument.withSummary(
            "Speaker 2 agreed to ship. Speaker 21 did not.", by: "m",
            in: "# Transcript\n\n**Speaker 2** [00:01]: Ship it.\n")
        let renamed = SpeakerNames.rename(in: markdown, ["Speaker 2": "John Doe"])
        #expect(
            TranscriptDocument(markdown: renamed).summary?.text
                == "John Doe agreed to ship. Speaker 21 did not.")
        #expect(renamed.contains("**John Doe** [00:01]"))
    }
}

@Suite struct AnthropicMessagesTests {
    @Test func requestUsesTheMessagesAPIShape() throws {
        let request = try AnthropicMessages.request(
            baseURL: try #require(URL(string: "https://api.anthropic.com")), apiKey: "k",
            model: "claude-opus-5", system: "sys", user: "usr")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body =
            try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["system"] as? String == "sys")
        #expect(body?["max_tokens"] as? Int == 16_000)
        #expect((body?["messages"] as? [[String: String]])?.first?["content"] == "usr")
    }

    @Test func fallbacksOnlyForAnthropicItself() throws {
        let direct = try AnthropicMessages.request(
            baseURL: try #require(URL(string: "https://api.anthropic.com")), apiKey: "k",
            model: "m", system: "s", user: "u")
        let proxied = try AnthropicMessages.request(
            baseURL: try #require(URL(string: "http://gateway.local/anthropic")), apiKey: "k",
            model: "m", system: "s", user: "u")
        #expect(
            direct.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(proxied.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(proxied.url?.absoluteString == "http://gateway.local/anthropic/v1/messages")
    }

    @Test func textBlocksAreJoinedAndARefusalThrows() throws {
        let ok = Data(
            #"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"Notes"}]}"#
                .utf8)
        #expect(try AnthropicMessages.text(of: ok) == "Notes")
        let refused = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        #expect(throws: AnthropicMessages.Failure.self) { try AnthropicMessages.text(of: refused) }
    }
}

@Suite struct SplitSummaryTests {
    /// A model that rejects anything longer than `limit` characters, like an API over its context.
    private actor Model {
        let limit: Int
        private(set) var calls: [String] = []
        init(limit: Int) { self.limit = limit }

        func complete(system: String, user: String) throws -> String {
            calls.append(user)
            guard user.count <= limit else {
                throw OpenAIChat.Failure.http(
                    400, "This model's maximum context length is exceeded")
            }
            return system.contains("one part") ? "note(\(user.count))" : "summary of \(user.count)"
        }
    }

    @Test func aTranscriptThatFitsIsSummarizedInOneCall() async throws {
        let model = Model(limit: 1_000)
        let text = try await SplitSummary.summarize(
            (1...5).map { "Me: line \($0)" }.joined(separator: "\n"), language: "English"
        ) { try await model.complete(system: $0, user: $1) }
        #expect(text.hasPrefix("summary of"))
        #expect(await model.calls.count == 1)
    }

    @Test func aTranscriptOverTheContextIsSplitThenCombined() async throws {
        let model = Model(limit: 300)
        let transcript = (1...40).map { "Speaker 1: this is line number \($0)" }.joined(
            separator: "\n")
        let text = try await SplitSummary.summarize(transcript, language: "English") {
            try await model.complete(system: $0, user: $1)
        }
        #expect(text.hasPrefix("summary of"))
        #expect(await model.calls.filter { $0.count > 300 }.count >= 1)
    }

    @Test func otherErrorsAreNotRetried() async {
        await #expect(throws: OpenAIChat.Failure.self) {
            try await SplitSummary.summarize("Me: hi", language: "English") { _, _ in
                throw OpenAIChat.Failure.http(401, "invalid key")
            }
        }
    }

    @Test func recognisesContextErrorsAcrossProviders() {
        #expect(
            SplitSummary.isContextOverflow(
                OpenAIChat.Failure.http(400, "maximum context length is 32768 tokens")))
        #expect(
            SplitSummary.isContextOverflow(
                AnthropicMessages.Failure.http(400, "prompt is too long: 250000 tokens")))
        #expect(SplitSummary.isContextOverflow(OpenAIChat.Failure.http(413, "")))
        #expect(!SplitSummary.isContextOverflow(OpenAIChat.Failure.http(429, "rate limited")))
    }
}

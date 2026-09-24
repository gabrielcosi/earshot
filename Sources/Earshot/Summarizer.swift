import EarshotKit
import Foundation
import FoundationModels

/// Writes a transcript's notes with Apple's on-device model, or with a model behind an
/// OpenAI-compatible endpoint the user configured.
enum Summarizer {
    enum Engine: String, CaseIterable, Identifiable {
        case apple
        case openAI
        case anthropic

        var id: String { rawValue }
    }

    enum Failure: LocalizedError {
        case unavailable
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Intelligence is off or unavailable on this Mac."
            case .notConfigured: "Set the endpoint's address and model in Settings."
            }
        }
    }

    struct Endpoint {
        let baseURL: URL
        let model: String
        let apiKey: String?
    }

    /// What the on-device model can read before macOS 27 reports its context: 4,096 tokens
    /// including instructions and answer, at about 4 characters a token.
    static let fallbackChunkCharacters = 6_000
    /// Room left for the answer in every call. Measured notes for a two-minute transcript were about
    /// 200 tokens; a part's notes run longer, and 1,024 covers them.
    private static let answerTokens = 1_024

    /// Returns the notes and who wrote them, for the credit line above the summary.
    static func summarize(
        _ transcript: String, language: String, engine: Engine, endpoint: Endpoint?
    )
        async throws -> (text: String, model: String)
    {
        switch engine {
        case .apple:
            return (try await apple(transcript, language: language), "Apple's on-device model")
        case .openAI, .anthropic:
            guard let endpoint else { throw Failure.notConfigured }
            let text = try await SplitSummary.summarize(transcript, language: language) {
                system, user in
                engine == .openAI
                    ? try await OpenAIChat.complete(
                        baseURL: endpoint.baseURL, apiKey: endpoint.apiKey, model: endpoint.model,
                        system: system, user: user)
                    : try await AnthropicMessages.complete(
                        baseURL: endpoint.baseURL, apiKey: endpoint.apiKey, model: endpoint.model,
                        system: system, user: user)
            }
            return (
                text,
                "\(endpoint.model) at \(endpoint.baseURL.host() ?? endpoint.baseURL.absoluteString)"
            )
        }
    }

    /// Short transcripts in one pass; long ones as notes per part, then those notes summarized.
    private static func apple(_ transcript: String, language: String) async throws -> String {
        guard SystemLanguageModel.default.availability == .available else {
            throw Failure.unavailable
        }
        let limit = await chunkCharacters(
            for: transcript, instructions: SummaryPrompt.partInstructions(language: language))
        var text = transcript
        while text.count > limit {
            var notes: [String] = []
            for chunk in SummaryPrompt.chunks(of: text, limit: limit) {
                let session = LanguageModelSession(
                    instructions: SummaryPrompt.partInstructions(language: language))
                notes.append(try await session.respond(to: chunk).content)
            }
            text = notes.joined(separator: "\n\n")
        }
        let session = LanguageModelSession(
            instructions: SummaryPrompt.instructions(language: language))
        return try await session.respond(to: text).content
    }

    /// How much transcript fits in one call, from the context the model reports and the tokens
    /// this text actually takes (macOS 27). A 10% margin covers parts that tokenize denser than
    /// the transcript as a whole.
    static func chunkCharacters(for text: String, instructions: String) async -> Int {
        guard #available(macOS 27.0, *) else { return fallbackChunkCharacters }
        let model = SystemLanguageModel.default
        guard let textTokens = try? await model.tokenCount(for: text), textTokens > 0,
            let instructionTokens = try? await model.tokenCount(for: Instructions(instructions))
        else { return fallbackChunkCharacters }
        let budget = model.contextSize - instructionTokens - answerTokens
        let charactersPerToken = Double(text.count) / Double(textTokens)
        return max(fallbackChunkCharacters / 2, Int(Double(budget) * charactersPerToken * 0.9))
    }
}

import Foundation

/// What a summarizer is told, and how a long transcript is split for a model with a small context.
public enum SummaryPrompt {
    public static func instructions(language: String) -> String {
        """
        You write notes from a transcript of a meeting, call, talk, or video. Write in \(language). Use Markdown \
        with these parts, and leave out a part that has nothing:
        a short paragraph on what it was about and what came of it;
        **Decisions**, a bullet list;
        **Action items**, a bullet list, starting each with the owner in bold when a person \
        is named.
        Only list a decision that was actually agreed, and an action item that someone \
        committed to do. Casual talk, a podcast, or an interview usually has neither: then \
        leave those parts out. Refer to people by the labels or names in the transcript. Do \
        not add anything the transcript does not say.
        """
    }

    /// Instructions for one part of a transcript too long to read at once; the notes of all parts
    /// are summarized again at the end.
    public static func partInstructions(language: String) -> String {
        """
        This is one part of a longer transcript. Write concise bullet notes in \
        \(language): topics, decisions, action items with owners, and open questions. Keep \
        names and numbers exactly. Do not add anything the transcript does not say.
        """
    }

    /// Splits at line boundaries so no line is cut; a single line longer than the limit becomes
    /// its own chunk.
    public static func chunks(of transcript: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in transcript.split(separator: "\n", omittingEmptySubsequences: false) {
            if !current.isEmpty, current.count + 1 + line.count > limit {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// The chat-completions call every OpenAI-compatible server answers: OpenAI, LiteLLM, Ollama,
/// llama.cpp, and gateways in front of them.
public enum OpenAIChat {
    public enum Failure: LocalizedError {
        case http(Int, String)
        case empty

        public var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                "The server answered HTTP \(status): \(body.prefix(200))"
            case .empty: "The server returned no text."
            }
        }
    }

    public static func request(
        baseURL: URL, apiKey: String?, model: String, system: String, user: String
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            Body(
                model: model,
                messages: [
                    Message(role: "system", content: system), Message(role: "user", content: user),
                ]))
        return request
    }

    public static func complete(
        baseURL: URL, apiKey: String?, model: String, system: String, user: String
    ) async throws -> String {
        var request = try request(
            baseURL: baseURL, apiKey: apiKey, model: model, system: system, user: user)
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.http(status, String(bytes: data, encoding: .utf8) ?? "")
        }
        return try content(of: data)
    }

    static func content(of data: Data) throws -> String {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let text = response.choices.first?.message.content, !text.isEmpty else {
            throw Failure.empty
        }
        return text
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct Body: Encodable {
        let model: String
        let messages: [Message]
    }

    private struct Choice: Decodable {
        let message: Message
    }

    private struct Response: Decodable {
        let choices: [Choice]
    }
}

/// Anthropic's Messages API over plain HTTP; there is no official Swift SDK.
public enum AnthropicMessages {
    public enum Failure: LocalizedError {
        case http(Int, String)
        case refused
        case empty

        public var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                "The server answered HTTP \(status): \(body.prefix(200))"
            case .refused: "The model declined to summarize this transcript."
            case .empty: "The server returned no text."
            }
        }
    }

    /// A non-streaming request: 16,000 output tokens is far more than notes need and keeps the
    /// response inside HTTP timeouts.
    static let maxTokens = 16_000

    public static func request(
        baseURL: URL, apiKey: String?, model: String, system: String, user: String
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let apiKey, !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        // Anthropic routes a refused request to another model itself. Gateways in front of the
        // API may not know the field, so it is only sent to Anthropic directly.
        let direct = baseURL.host() == "api.anthropic.com"
        if direct {
            request.setValue(
                "server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(
            AnthropicBody(
                model: model, maxTokens: maxTokens, system: system,
                messages: [AnthropicMessage(role: "user", content: user)],
                fallbacks: direct ? "default" : nil))
        return request
    }

    public static func complete(
        baseURL: URL, apiKey: String?, model: String, system: String, user: String
    ) async throws -> String {
        var request = try request(
            baseURL: baseURL, apiKey: apiKey, model: model, system: system, user: user)
        request.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.http(status, String(bytes: data, encoding: .utf8) ?? "")
        }
        return try text(of: data)
    }

    static func text(of data: Data) throws -> String {
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        if response.stopReason == "refusal" { throw Failure.refused }
        let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

}

/// Summarizes through any model call, sending the whole transcript when it fits and splitting it
/// when the model says it does not. APIs rarely say their context size up front, but they all
/// reject an oversized request, so the rejection is the signal.
public enum SplitSummary {
    public typealias Complete = @Sendable (_ system: String, _ user: String) async throws -> String

    public static func summarize(_ transcript: String, language: String, complete: Complete)
        async throws -> String
    {
        do {
            return try await complete(SummaryPrompt.instructions(language: language), transcript)
        } catch  where isContextOverflow(error) {
            let notes = try await notes(for: transcript, language: language, complete: complete)
            return try await summarize(notes, language: language, complete: complete)
        }
    }

    /// Notes for each half, splitting a half again while it is still too long.
    private static func notes(for text: String, language: String, complete: Complete)
        async throws -> String
    {
        let halves = SummaryPrompt.chunks(of: text, limit: max(1, (text.count + 1) / 2))
        guard halves.count > 1 else {
            throw OpenAIChat.Failure.http(413, "a single line is too long")
        }
        var notes: [String] = []
        for half in halves {
            do {
                notes.append(
                    try await complete(SummaryPrompt.partInstructions(language: language), half))
            } catch  where isContextOverflow(error) {
                notes.append(
                    try await self.notes(for: half, language: language, complete: complete))
            }
        }
        return notes.joined(separator: "\n\n")
    }

    /// The wording differs by server: OpenAI and vLLM say "maximum context length", llama.cpp
    /// "exceeds the available context size", Anthropic "prompt is too long". A 413 is too large
    /// by definition.
    public static func isContextOverflow(_ error: any Error) -> Bool {
        let (status, body): (Int, String)
        switch error {
        case OpenAIChat.Failure.http(let code, let text): (status, body) = (code, text)
        case AnthropicMessages.Failure.http(let code, let text): (status, body) = (code, text)
        default: return false
        }
        if status == 413 { return true }
        guard status == 400 else { return false }
        let text = body.lowercased()
        return [
            "context length", "context size", "context window", "too long", "too many tokens",
            "maximum context",
        ]
        .contains { text.contains($0) }
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [AnthropicMessage]
    let fallbacks: String?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, fallbacks
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicBlock: Decodable {
    let type: String
    let text: String?
}

private struct AnthropicResponse: Decodable {
    let stopReason: String?
    let content: [AnthropicBlock]

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

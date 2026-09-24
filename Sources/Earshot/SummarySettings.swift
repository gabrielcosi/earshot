import EarshotKit
import SwiftUI

/// Where notes are written: on this Mac by default, or by a model behind an
/// OpenAI-compatible endpoint.
struct SummarySettings: View {
    @Environment(SessionController.self) private var controller
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        @Bindable var preferences = controller.preferences
        Section {
            Picker("Written by", selection: $preferences.summaryEngine) {
                Text("This Mac (Apple Intelligence)").tag(Summarizer.Engine.apple)
                Text("An OpenAI-compatible API").tag(Summarizer.Engine.openAI)
                Text("The Anthropic API").tag(Summarizer.Engine.anthropic)
            }
            if preferences.summaryEngine != .apple {
                TextField(
                    "Address", text: $preferences.summaryBaseURL,
                    prompt: Text(
                        preferences.summaryEngine == .openAI
                            ? "https://api.openai.com/v1" : "https://api.anthropic.com"))
                TextField(
                    "Model", text: $preferences.summaryModel,
                    prompt: Text(
                        preferences.summaryEngine == .openAI ? "gpt-4.1-mini" : "claude-opus-5"))
                SecureField("API key", text: $preferences.summaryAPIKey, prompt: Text("Optional"))
                HStack {
                    if let testResult {
                        Text(testResult).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button(testing ? "Testing…" : "Test Connection", action: test)
                        .disabled(testing || preferences.summaryEndpoint == nil)
                }
            }
            Toggle("Summarize when listening stops", isOn: $preferences.summarizeAutomatically)
        } header: {
            Text("Summaries")
        } footer: {
            Text(
                preferences.summaryEngine == .apple
                    ? "Notes are written on this Mac and nothing leaves it. Long transcripts are summarized in parts, then combined."
                    : "The transcript is sent to this address to be summarized. The API key is kept in your keychain."
            )
        }
    }

    private func test() {
        guard let endpoint = controller.preferences.summaryEndpoint else { return }
        testing = true
        Task {
            do {
                let reply =
                    controller.preferences.summaryEngine == .openAI
                    ? try await OpenAIChat.complete(
                        baseURL: endpoint.baseURL, apiKey: endpoint.apiKey, model: endpoint.model,
                        system: "Answer in one word.", user: "Reply with OK.")
                    : try await AnthropicMessages.complete(
                        baseURL: endpoint.baseURL, apiKey: endpoint.apiKey, model: endpoint.model,
                        system: "Answer in one word.", user: "Reply with OK.")
                testResult = "Connected: \(reply.prefix(40))"
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}

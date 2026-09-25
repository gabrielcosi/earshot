import EarshotKit
import Foundation
import FoundationModels

/// Suggests names for speaker labels from what the transcript itself says, with Apple's
/// on-device model: introductions ("I'm John Doe") and being addressed by name.
enum SpeakerSuggester {
    struct Suggestion: Equatable {
        let name: String
        let evidence: String
    }

    @Generable
    struct Found {
        @Guide(description: "The speaker label exactly as written, like \"Speaker 2\"")
        var label: String
        @Guide(description: "The person's name as said in the transcript")
        var name: String
        // Never shown: the quote shown is the transcript's own sentence. Asking for it keeps the
        // model grounded: without it, it named a speaker in a transcript where nobody gave a
        // name in 5 of 5 runs, against 1 of 5 with it.
        @Guide(description: "The words from the transcript that show this label is this person")
        var evidence: String
    }

    @Generable
    struct Answer {
        var speakers: [Found]
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private static let instructions = """
        You identify speakers in a transcript. Each line starts with a speaker label in \
        bold. Only name a label when the transcript shows it: the speaker introduces themselves \
        ("I'm John Doe"), or the next speaker addresses them by name right after they spoke. \
        Never guess. Omit labels you cannot name.
        """

    /// Nil when the model is unavailable or fails, so the sheet does not claim it found no one.
    static func suggest(for markdown: String, labels: [String]) async -> [String: Suggestion]? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        // Introductions come early, so the opening of the transcript, as much as fits, is what
        // the model reads. Measured: 3.2 s for a two-minute podcast.
        let excerpt = await Summarizer.chunkCharacters(for: markdown, instructions: instructions)
        guard
            let answer = try? await session.respond(
                to: "Transcript:\n\(markdown.prefix(excerpt))", generating: Answer.self)
        else { return nil }
        return answer.content.speakers.reduce(into: [:]) { result, found in
            let name = found.name.trimmingCharacters(in: .whitespaces)
            guard labels.contains(found.label),
                let evidence = SpeakerNames.evidence(for: name, in: markdown)
            else { return }
            result[found.label] = Suggestion(name: name, evidence: evidence)
        }
    }
}

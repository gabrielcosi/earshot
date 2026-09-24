import EarshotKit
import Foundation

/// Notes: written on request or when a session ends, into the transcript's own file above
/// its transcript.
extension SessionController {
    func summarize(_ file: URL) async {
        guard !summarizing.contains(file),
            let markdown = try? String(contentsOf: file, encoding: .utf8)
        else { return }
        let transcript = TranscriptDocument(markdown: markdown).transcriptText
        guard !transcript.isEmpty else { return }
        summarizing.insert(file)
        defer { summarizing.remove(file) }
        do {
            let (text, model) = try await Summarizer.summarize(
                transcript, language: Languages.displayName(primaryLanguage),
                engine: preferences.summaryEngine, endpoint: preferences.summaryEndpoint)
            if file == savedFile {
                summary = TranscriptDocument.Summary(text: text, model: model)
                save()
            } else {
                try TranscriptDocument.withSummary(text, by: model, in: markdown).write(
                    to: file, atomically: true, encoding: .utf8)
            }
            changedFile = file
        } catch {
            log.error("summary failed: \(error, privacy: .public)")
            lastError = "Summary failed: \(error.localizedDescription)"
        }
    }

    /// Called once the session that just ended is done with naming, so the notes use the names.
    func sessionFinished() {
        guard preferences.summarizeAutomatically, let file = savedFile else { return }
        Task { await summarize(file) }
    }
}

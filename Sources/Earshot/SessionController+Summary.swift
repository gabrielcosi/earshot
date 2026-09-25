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
            problems.report(.summaryFailed)
        }
    }

    /// A session that just ended with speakers to name, for the naming sheet.
    struct NamingRequest: Equatable {
        let file: URL
        /// Only a stop the user pressed brings the window up; otherwise the sheet waits for the
        /// next time the window opens.
        let opensWindow: Bool
    }

    /// Every stopped session goes through here, whether stopped from the menu or ended by a lost
    /// engine: one with speakers to name asks for its naming sheet, and is summarized after it.
    func sessionEnded(byUser: Bool) {
        if let file = savedFile, let markdown = try? String(contentsOf: file, encoding: .utf8),
            !SpeakerNames.speakers(in: markdown).isEmpty
        {
            namingRequest = NamingRequest(file: file, opensWindow: byUser)
        } else {
            sessionFinished()
        }
    }

    /// Called once the session that just ended is done with naming, so the notes use the names.
    func sessionFinished() {
        guard preferences.summarizeAutomatically, let file = savedFile else { return }
        Task { await summarize(file) }
    }
}

import EarshotKit
import Foundation

/// Notes: written on request or when a session ends, stored with the transcript and written
/// above it in its Markdown file.
extension SessionController {
    func summarize(_ transcript: UUID) async {
        guard !summarizing.contains(transcript),
            let view = try? store.view(transcript)
        else { return }
        let text = view.transcriptText(rules: rules)
        guard !text.isEmpty else { return }
        summarizing.insert(transcript)
        defer { summarizing.remove(transcript) }
        do {
            let (summary, model) = try await Summarizer.summarize(
                text, language: Languages.displayName(primaryLanguage),
                engine: preferences.summaryEngine, endpoint: preferences.summaryEndpoint)
            // Written against the store as it is now: only the summary changes, brought up to
            // any names given while it was being written.
            try store.setSummary(summary, model: model, for: transcript, labelsAtStart: view.labels)
            scheduleExport(transcript)
            dismissSummaryFailure(transcript)
        } catch {
            log.error("summary failed: \(error, privacy: .public)")
            let failure: Problem = .summaryFailed(
                SummaryFailure(error)
                    ?? (error as? Summarizer.Failure == .unavailable
                        ? .appleIntelligenceUnavailable : nil))
            failedSummaries[transcript] = failure
            problems.report(failure)
        }
    }

    /// The menu's report stands for every failed summary, so it goes with the last of them.
    func dismissSummaryFailure(_ transcript: UUID) {
        failedSummaries[transcript] = nil
        guard failedSummaries.isEmpty else { return }
        problems.resolve { if case .summaryFailed = $0 { true } else { false } }
    }

    /// A session that just ended with speakers to name, for the naming sheet.
    struct NamingRequest: Equatable {
        let transcript: UUID
        /// Only a stop the user pressed brings the window up; otherwise the sheet waits for the
        /// next time the window opens.
        let opensWindow: Bool
    }

    /// Every stopped session goes through here, whether stopped from the menu or ended by a lost
    /// engine: one with speakers to name asks for its naming sheet, and is summarized after it.
    func sessionEnded(byUser: Bool) {
        // Naming and a summary cannot finish once the app is gone.
        guard !quitting else { return }
        if let savedID, let view = try? store.view(savedID), !view.speakersToName().isEmpty {
            namingRequest = NamingRequest(transcript: savedID, opensWindow: byUser)
        } else {
            sessionFinished()
        }
    }

    /// Called once the session that just ended is done with naming, so the notes use the names.
    func sessionFinished() {
        guard preferences.summarizeAutomatically, let savedID else { return }
        Task { await summarize(savedID) }
    }
}

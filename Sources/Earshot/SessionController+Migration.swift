import EarshotKit
import Foundation

/// Transcripts Earshot 0.1 saved as Markdown files, brought into the store once.
extension SessionController {
    /// Runs at launch, before any export, so every file it lists was there before this launch
    /// wrote anything, and again when the user chooses the folder, until one run finishes. A
    /// folder chosen while it runs gets a run of its own after it. The files are only read. A chosen folder that no longer opens is not swapped for the default:
    /// its transcripts wait until the user chooses it again.
    func importEarlierTranscripts() async {
        guard !importing else { return }
        guard !preferences.transcriptsFolderLost else {
            problems.report(.transcriptsFolderUnavailable)
            return
        }
        problems.resolve { $0 == .transcriptsFolderUnavailable }
        importing = true
        let migration = TranscriptMigration(store: store, audioFolder: Self.audioFolder)
        var folder: URL
        repeat {
            let current = preferences.transcriptsFolder
            folder = current
            do {
                try await Self.run(migration, in: current) {
                    await MainActor.run { self.preferences.transcriptsFolder == current }
                } progress: { done, total in
                    await MainActor.run { self.importProgress = (done, total) }
                }
                problems.resolve { $0.id == "importFailed" }
            } catch {
                log.error("importing Earshot 0.1's transcripts failed: \(error, privacy: .public)")
                problems.report(.importFailed(Self.actionable(error)))
            }
        } while folder != preferences.transcriptsFolder && !preferences.transcriptsFolderLost
        importProgress = nil
        importing = false
        unimportedFiles = (try? store.unimportedFiles()) ?? []
    }

    @concurrent
    nonisolated private static func run(
        _ migration: TranscriptMigration, in folder: URL,
        isCurrent: @escaping @Sendable () async -> Bool,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws {
        try await migration.run(in: folder, progress: progress, isCurrent: isCurrent)
    }
}

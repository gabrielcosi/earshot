import EarshotKit
import Foundation
import Observation

/// The stored transcripts, with what the sidebar shows of each, kept current as the store changes.
@Observable
final class SavedTranscripts {
    private(set) var entries: [TranscriptStore.Entry] = []
    /// The store could not be read; the sidebar says so.
    private(set) var unreadable = false

    func follow(_ store: TranscriptStore) async {
        do {
            for try await entries in store.listChanges() {
                self.entries = entries
                unreadable = false
            }
        } catch {
            unreadable = true
        }
    }
}

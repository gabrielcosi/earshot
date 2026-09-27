import Foundation
import GRDB
import Testing

@testable import EarshotKit

/// Renaming and deleting transcripts: a title is one line, a delete removes every row and hands
/// back the audio to remove, and nothing late brings a deleted transcript back.
@Suite struct TranscriptManagementTests {
    private let store: TranscriptStore
    private let id = UUID()
    private let started = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        store = try TranscriptStore.inMemory()
    }

    private func final(_ text: String, speaker: Int? = nil, at start: Double) -> Transcript {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: text,
            words: [Word(word: text, start: start, end: start + 1, speaker: speaker)],
            on: speaker == nil ? .microphone : .system)
        return transcript
    }

    /// A save that lands after its transcript was deleted, such as a late refinement, does not
    /// bring the transcript back.
    @Test func aLateSaveDoesNotBringADeletedTranscriptBack() throws {
        var transcript = final("one", speaker: 1, at: 0)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        let saved = transcript.utterances
        try store.delete([id])

        transcript.applyFinal(
            transcript: "two", words: [Word(word: "two", start: 5, end: 6, speaker: 2)],
            on: .system)
        try store.saveLive(
            id, startedAt: started, utterances: transcript.utterances, previous: saved)
        #expect(try store.list().isEmpty)
    }

    /// A sealed transcript with a row in every table that hangs off it.
    private func fullTranscript(_ transcript: UUID, audio: String?) throws {
        let utterances = final("Hallo", speaker: 1, at: 0).utterances
        let paragraph = try #require(utterances.first?.id)
        try store.saveLive(transcript, startedAt: started, utterances: utterances)
        try store.setTranslation("Hello", of: "Hallo", language: "en", for: paragraph)
        try store.setEdit(ParagraphEdit(text: "Hi"), of: paragraph)
        try store.seal(transcript, at: started)
        try store.setNames([.remote(slot: 1): "Jane"], in: transcript)
        try store.setSummary("s", model: "m", for: transcript, labelsAtStart: [:])
        try store.setAudio(audio, for: transcript)
        try store.recordExport(
            of: transcript, at: URL(filePath: "/tmp/\(transcript).md"), contents: Data())
    }

    /// Deleting removes every row the transcripts hold, in one go, and hands back their kept
    /// audio by the name the store has for it, to remove once the rows are gone.
    @Test func deletingTranscriptsRemovesTheirRowsAndReturnsTheirAudio() throws {
        let (other, kept) = (UUID(), UUID())
        try fullTranscript(id, audio: "\(id.uuidString).m4a")
        try fullTranscript(other, audio: "imported-copy.m4a")
        try fullTranscript(kept, audio: "\(kept.uuidString).m4a")

        let audio = try store.delete([id, other])
        #expect(Set(audio) == ["\(id.uuidString).m4a", "imported-copy.m4a"])
        #expect(try store.list().map(\.id) == [kept])
        let tables = [
            "paragraph", "paragraph_edit", "speaker_name", "translation", "summary",
            "local_export",
        ]
        let counts = try store.writer.read { db in
            try tables.map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") }
        }
        #expect(counts == tables.map { _ in 1 })
    }

    @Test func deletingATranscriptWithoutAudioReturnsNone() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hi", at: 0).utterances)
        #expect(try store.delete([id]).isEmpty)
        #expect(try store.delete([UUID()]).isEmpty)
    }

    /// A summary that lands after its transcript was deleted is not stored, and says so, so no
    /// export is scheduled for it.
    @Test func aSummaryForADeletedTranscriptIsNotStored() throws {
        try fullTranscript(id, audio: nil)
        #expect(try store.setSummary("t", model: "m", for: id, labelsAtStart: [:]))
        try store.delete([id])
        #expect(try !store.setSummary("t", model: "m", for: id, labelsAtStart: [:]))
        #expect(
            try store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM summary") } == 0
        )
    }

    private var pendingRemovals: [String] {
        get throws {
            try store.writer.read {
                try String.fetchAll($0, sql: "SELECT name FROM local_pending_removal ORDER BY name")
            }
        }
    }

    /// The audio to remove is recorded with the delete, in its transaction, so a crash before the
    /// files are gone leaves the names for the next launch. The files themselves are left for
    /// the caller to remove after the commit.
    @Test func deletingRecordsItsAudioToRemoveWithTheRows() throws {
        let folder = try audioFolder(with: ["a.m4a"])
        defer { try? FileManager.default.removeItem(at: folder) }
        try fullTranscript(id, audio: "a.m4a")
        try store.saveLive(UUID(), startedAt: started, utterances: final("Hi", at: 0).utterances)

        #expect(try store.delete([id]) == ["a.m4a"])
        #expect(try pendingRemovals == ["a.m4a"])
        #expect(try files(in: folder) == ["a.m4a"])
    }

    /// Removing the deleted audio, after a delete or at the next launch, removes each file and
    /// then its name; a file already gone counts as removed. It removes nothing else: a file no
    /// transcript has but that was never deleted, such as one kept while the store could not be
    /// opened, stays.
    @Test func onlyDeletedAudioIsRemovedAndThenForgotten() throws {
        let folder = try audioFolder(with: ["a.m4a", "kept.m4a", "unrecorded.m4a"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let (other, kept) = (UUID(), UUID())
        try fullTranscript(id, audio: "a.m4a")
        try fullTranscript(other, audio: "gone.m4a")
        try fullTranscript(kept, audio: "kept.m4a")
        try store.delete([id, other])

        #expect(try store.removeDeletedAudio(in: folder) == ["a.m4a", "gone.m4a"])
        #expect(try pendingRemovals.isEmpty)
        #expect(try files(in: folder) == ["kept.m4a", "unrecorded.m4a"])
        #expect(try store.removeDeletedAudio(in: folder).isEmpty)
    }

    private func audioFolder(with names: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names { try Data("x".utf8).write(to: folder.appending(path: name)) }
        return folder
    }

    private func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .sorted()
    }

    /// A title is one line: a newline would put lines in the Markdown file's heading that read as
    /// transcript lines.
    @Test func aTitleIsStoredAsOneTrimmedLine() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hi", at: 0).utterances)
        #expect(try store.setTitle("  Plan\n**Me** [00:01.00]: hi \n", of: id) == .some(nil))
        #expect(try store.list().first?.title == "Plan **Me** [00:01.00]: hi")
    }

    /// Nothing to undo: the title is as it was, or there is no such transcript.
    @Test func anUnchangedTitleOrAnUnknownTranscriptChangesNothing() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hi", at: 0).utterances)
        try store.setTitle("Weekly sync", of: id)
        #expect(try store.setTitle(" Weekly sync", of: id) == nil)
        #expect(try store.setTitle("Gone", of: UUID()) == nil)
    }

    /// An empty title gives the transcript Earshot's own back, and undo the one it had.
    @Test func anEmptyTitleGivesBackEarshotsOwn() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hi", at: 0).utterances)
        try store.setTitle("Weekly sync", of: id)
        #expect(try store.setTitle(" \n ", of: id) == "Weekly sync")
        #expect(try store.view(id)?.title == nil)
    }
}

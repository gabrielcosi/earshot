import Foundation
import GRDB
import Testing

@testable import EarshotKit

@Suite struct TranscriptStoreTests {
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

    @Test func thereIsNoTranscriptUntilItsFirstFinal() throws {
        try store.saveLive(id, startedAt: started, utterances: [])
        #expect(try store.list().isEmpty)
        #expect(try store.view(id) == nil)
    }

    @Test func theFirstFinalCreatesTheTranscriptWithItsLine() throws {
        let transcript = final("Hello there", speaker: 1, at: 2)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)

        let entry = try #require(try store.list().first)
        #expect(entry.id == id)
        #expect(entry.startedAt == started)
        #expect(entry.title == nil)
        let view = try #require(try store.view(id))
        #expect(view.paragraphs.map(\.text) == ["Hello there"])
        #expect(view.paragraphs.map(\.speaker) == [.remote(slot: 1)])
        #expect(view.endedAt == nil)
    }

    /// Finals merge into the paragraph before them, refinements rewrite it, and relabelling
    /// replaces paragraphs: the store follows each, with nothing left over from before.
    @Test func eachSaveLeavesTheStoreHoldingExactlyTheSessionsParagraphs() throws {
        var transcript = Transcript()
        var saved: [Utterance] = []
        func save() throws {
            try store.saveLive(
                id, startedAt: started, utterances: transcript.utterances, previous: saved)
            saved = transcript.utterances
        }
        let first = transcript.applyFinal(
            transcript: "one", words: [Word(word: "one", start: 0, end: 1, speaker: 1)],
            on: .system)
        try save()
        transcript.applyFinal(
            transcript: "two", words: [Word(word: "two", start: 1, end: 2, speaker: 1)],
            on: .system)
        transcript.refine(first, with: [Word(word: "won", start: 0, end: 1)])
        try save()
        #expect(try store.view(id)?.paragraphs.map(\.text) == ["won two"])

        transcript.applyFinal(
            transcript: "three", words: [Word(word: "three", start: 2, end: 3, speaker: 2)],
            on: .system)
        transcript.applyFinal(
            transcript: "four", words: [Word(word: "four", start: 4, end: 5, speaker: 1)],
            on: .system)
        try save()
        // An earlier line lands in the middle, and the one after it moves down a place.
        transcript.applyFinal(
            transcript: "me", words: [Word(word: "me", start: 0.5, end: 0.8)], on: .microphone)
        try save()
        #expect(try store.view(id)?.paragraphs.map(\.text) == ["won two", "me", "three", "four"])
        #expect(
            try store.writer.read {
                try Int.fetchAll($0, sql: #"SELECT position FROM paragraph ORDER BY "start""#)
            } == [0, 1, 2, 3])

        transcript.relabel([
            TranscribedTurn(
                turn: SpeakerTurn(start: 0, end: 2, speaker: 2),
                words: [Word(word: "one", start: 0, end: 1), Word(word: "two", start: 1, end: 2)])
        ])
        try save()
        let view = try #require(try store.view(id))
        #expect(view.paragraphs.map(\.id) == transcript.utterances.map(\.id))
        #expect(view.paragraphs.map(\.speaker) == transcript.utterances.map(\.speaker))
        #expect(view.paragraphs.map(\.text) == transcript.utterances.map(\.text))
    }

    /// A crash loses nothing: every save is committed when it returns, so a store opened again
    /// from the same file, as the next launch does, has it.
    @Test func aSavedLineSurvivesTheStoreBeingOpenedAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Earshot.sqlite")
        let running = try TranscriptStore.open(at: file)
        let transcript = final("Nothing is lost", at: 0)
        try running.saveLive(id, startedAt: started, utterances: transcript.utterances)

        let relaunched = try TranscriptStore.open(at: file)
        #expect(try relaunched.view(id)?.paragraphs.map(\.text) == ["Nothing is lost"])
    }

    @Test func launchSealsUnfinishedTranscriptsAtTheirLastLine() throws {
        try store.saveLive(id, startedAt: started, utterances: final("cut off", at: 30).utterances)
        let finished = UUID()
        try store.saveLive(
            finished, startedAt: started, utterances: final("done", at: 0).utterances)
        try store.seal(finished, at: started.addingTimeInterval(99))

        #expect(try store.sealUnfinished() == [id])
        #expect(try store.view(id)?.endedAt == started.addingTimeInterval(31))
        #expect(try store.view(finished)?.endedAt == started.addingTimeInterval(99))
        #expect(try store.sealUnfinished().isEmpty)
    }

    /// Launch writes a Markdown file for every ended transcript that has none, and for no other.
    @Test func unexportedListsEndedTranscriptsWithoutAFile() throws {
        try store.saveLive(id, startedAt: started, utterances: final("ended", at: 0).utterances)
        try store.seal(id, at: started)
        try store.saveLive(
            UUID(), startedAt: started, utterances: final("recording", at: 0).utterances)
        #expect(try store.unexported() == [id])

        try store.recordExport(of: id, at: URL(filePath: "/tmp/ended.md"), contents: Data())
        #expect(try store.unexported().isEmpty)
    }

    @Test func aSealedTranscriptKeepsItsOriginalParagraphs() throws {
        try store.saveLive(id, startedAt: started, utterances: final("said", at: 0).utterances)
        try store.seal(id, at: started)
        try store.saveLive(id, startedAt: started, utterances: final("changed", at: 0).utterances)
        #expect(try store.view(id)?.paragraphs.map(\.text) == ["said"])
    }

    /// A summary takes up to a minute; a rename made meanwhile must not be undone by it.
    @Test func aSummaryStartedBeforeARenameLandsWithTheNewName() throws {
        try store.saveLive(
            id, startedAt: started, utterances: final("Hi", speaker: 2, at: 0).utterances)
        try store.seal(id, at: started)
        let labels = try #require(try store.view(id)).labels
        try store.setNames([.remote(slot: 2): "John Doe"], in: id)

        try store.setSummary("Speaker 2 opened.", model: "m", for: id, labelsAtStart: labels)
        let view = try #require(try store.view(id))
        #expect(view.summary == TranscriptDocument.Summary(text: "John Doe opened.", model: "m"))
        #expect(view.label(.remote(slot: 2)) == "John Doe")
    }

    @Test func aNewSummaryReplacesTheLastOne() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hi", at: 0).utterances)
        try store.setSummary("first", model: "a", for: id, labelsAtStart: [:])
        try store.setSummary("second", model: "b", for: id, labelsAtStart: [:])
        #expect(
            try store.view(id)?.summary == TranscriptDocument.Summary(text: "second", model: "b"))
        #expect(
            try store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM summary") } == 1
        )
    }

    @Test func aTranslationShowsOnlyWithTheTextItWasMadeFrom() throws {
        var transcript = Transcript()
        let final = transcript.applyFinal(
            transcript: "Hallo", words: [Word(word: "Hallo", start: 0, end: 1, speaker: 1)],
            on: .system)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        let paragraph = try #require(transcript.utterances.first?.id)
        try store.setTranslation("Hello", of: "Hallo", language: "en", for: paragraph)
        #expect(try store.view(id)?.paragraphs.first?.translation == "Hello")

        transcript.refine(final, with: [Word(word: "Halle", start: 0, end: 1)])
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        #expect(try store.view(id)?.paragraphs.first?.translation == nil)
    }

    /// Relabelling replaces paragraphs while their translations may still be on the way.
    @Test func aTranslationForAParagraphThatIsGoneIsDropped() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hallo", at: 0).utterances)
        try store.setTranslation("Hello", of: "Hallo", language: "en", for: UUID())
        #expect(try store.view(id)?.paragraphs.first?.translation == nil)
    }

    @Test func anEditOverridesTheViewAndKeepsTheOriginal() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "",
            words: [
                Word(word: "one", start: 0, end: 1, speaker: 1),
                Word(word: "two", start: 1, end: 2, speaker: 2),
                Word(word: "three", start: 2, end: 3, speaker: 1),
            ], on: .system)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        let ids = transcript.utterances.map(\.id)
        try store.setEdit(ParagraphEdit(text: "uno"), of: ids[0])
        try store.setEdit(ParagraphEdit(speaker: .remote(slot: 1)), of: ids[1])
        try store.setEdit(ParagraphEdit(deleted: true), of: ids[2])

        let view = try #require(try store.view(id))
        #expect(view.paragraphs.map(\.text) == ["uno", "two"])
        #expect(view.paragraphs.map(\.speaker) == [.remote(slot: 1), .remote(slot: 1)])
        #expect(try store.edit(of: ids[0]) == ParagraphEdit(text: "uno"))
        #expect(
            try store.writer.read {
                try String.fetchAll($0, sql: "SELECT text FROM paragraph ORDER BY position")
            }
                == ["one", "two", "three"])
    }

    /// Undo sets the edit that was there before, so setting one again replaces it, and clearing it
    /// shows the original.
    @Test func settingAnEditReplacesItAndClearingItRestoresTheOriginal() throws {
        try store.saveLive(id, startedAt: started, utterances: final("said", at: 0).utterances)
        let paragraph = try #require(try store.view(id)?.paragraphs.first?.id)
        try store.setEdit(ParagraphEdit(text: "first"), of: paragraph)
        try store.setEdit(ParagraphEdit(text: "second"), of: paragraph)
        #expect(try store.view(id)?.paragraphs.map(\.text) == ["second"])
        #expect(
            try store.writer.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM paragraph_edit")
            } == 1)

        try store.setEdit(nil, of: paragraph)
        #expect(try store.view(id)?.paragraphs.map(\.text) == ["said"])
    }

    @Test func revertingReturnsTheEditsSoTheyCanBeRestored() throws {
        try store.saveLive(id, startedAt: started, utterances: final("said", at: 0).utterances)
        let paragraph = try #require(try store.view(id)?.paragraphs.first?.id)
        try store.setEdit(ParagraphEdit(text: "edited"), of: paragraph)

        let reverted = try store.revertEdits(in: id)
        #expect(try store.view(id)?.paragraphs.map(\.text) == ["said"])
        for (paragraph, edit) in reverted { try store.setEdit(edit, of: paragraph) }
        #expect(try store.view(id)?.paragraphs.map(\.text) == ["edited"])
    }

    @Test func anEditedTranslationSourceHidesTheTranslation() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hallo", at: 0).utterances)
        let paragraph = try #require(try store.view(id)?.paragraphs.first?.id)
        try store.setTranslation("Hello", of: "Hallo", language: "en", for: paragraph)
        try store.setEdit(ParagraphEdit(text: "Hallo zusammen"), of: paragraph)
        #expect(try store.view(id)?.paragraphs.first?.translation == nil)
    }

    @Test func keptAudioIsRecordedByName() throws {
        try store.saveLive(id, startedAt: started, utterances: final("Hi", at: 0).utterances)
        #expect(try store.view(id)?.audio == nil)
        try store.setAudio("\(id.uuidString).m4a", for: id)
        #expect(try store.view(id)?.audio == "\(id.uuidString).m4a")
    }

    @Test func theListIsNewestFirstWithEachTranscriptsLength() throws {
        let older = UUID()
        try store.saveLive(older, startedAt: started, utterances: final("a", at: 10).utterances)
        try store.saveLive(
            id, startedAt: started.addingTimeInterval(60), utterances: final("b", at: 40).utterances
        )
        let entries = try store.list()
        #expect(entries.map(\.id) == [id, older])
        #expect(entries.map(\.length) == [41, 11])
    }
}

/// What iCloud sync will need later: every row has a UUID of its own, so records made on two Macs
/// never collide, and nothing but that key is unique, since CloudKit enforces no constraint.
@Suite struct TranscriptStoreSchemaTests {
    @Test func everyTableHasAUUIDPrimaryKeyAndNoOtherUniqueConstraint() throws {
        let store = try TranscriptStore.inMemory()
        try store.writer.read { db in
            let tables = try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master WHERE type = 'table'
                    AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                    """)
            #expect(
                Set(tables) == [
                    "transcript", "paragraph", "paragraph_edit", "speaker_name", "translation",
                    "summary", "local_export", "local_migration", "local_migration_file",
                ])
            for table in tables {
                let key = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                    .filter { $0["pk"] as Int > 0 }
                #expect(key.map { $0["name"] as String } == ["id"], "\(table)")
                #expect(key.map { $0["type"] as String } == ["BLOB"], "\(table)")
                let unique = try Row.fetchAll(db, sql: "PRAGMA index_list(\(table))")
                    .filter { $0["unique"] as Int == 1 && $0["origin"] as String != "pk" }
                #expect(unique.isEmpty, "\(table)")
                for foreignKey in try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(table))") {
                    #expect(
                        ["CASCADE", "SET NULL"].contains(foreignKey["on_delete"] as String),
                        "\(table)")
                }
            }
        }
    }

    @Test func deletingATranscriptDeletesEverythingItHolds() throws {
        let store = try TranscriptStore.inMemory()
        let id = UUID()
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Hallo", start: 0, end: 1, speaker: 1)],
            on: .system)
        let paragraph = try #require(transcript.utterances.first?.id)
        try store.saveLive(id, startedAt: .now, utterances: transcript.utterances)
        try store.setTranslation("Hello", of: "Hallo", language: "en", for: paragraph)
        try store.setEdit(ParagraphEdit(text: "Hi"), of: paragraph)
        try store.seal(id, at: .now)
        try store.setNames([.remote(slot: 1): "Jane"], in: id)
        try store.setSummary("s", model: "m", for: id, labelsAtStart: [:])
        try store.recordExport(of: id, at: URL(filePath: "/tmp/x.md"), contents: Data())

        try store.writer.write { db in
            _ = try db.execute(sql: "DELETE FROM transcript")
            for table in [
                "paragraph", "paragraph_edit", "speaker_name", "translation", "summary",
                "local_export",
            ] {
                #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") == 0, "\(table)")
            }
        }
    }
}

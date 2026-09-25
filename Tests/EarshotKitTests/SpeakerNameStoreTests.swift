import Foundation
import GRDB
import Testing

@testable import EarshotKit

/// Naming speakers in the store: what undo needs back, the summary's mentions, and the records.
@Suite struct SpeakerNameStoreTests {
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

    /// A sealed transcript with Speaker 1 then Speaker 2.
    private func twoSpeakers() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "",
            words: [
                Word(word: "Hi", start: 0, end: 1, speaker: 1),
                Word(word: "Hello", start: 2, end: 3, speaker: 2),
            ], on: .system)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        try store.seal(id, at: started)
    }

    @Test func namingRewritesTheSummarysMentions() throws {
        try twoSpeakers()
        try store.setSummary(
            "Speaker 2 opened. Speaker 22 did not.", model: "m", for: id, labelsAtStart: [:])

        try store.setNames([.remote(slot: 2): " John Doe "], in: id)
        let view = try #require(try store.view(id))
        #expect(view.label(.remote(slot: 2)) == "John Doe")
        #expect(view.summary?.text == "John Doe opened. Speaker 22 did not.")

        try store.setNames([.remote(slot: 2): "Jane"], in: id)
        #expect(try store.view(id)?.summary?.text == "Jane opened. Speaker 22 did not.")
    }

    /// Undo sets back what `setNames` returns, and redo sets back what that returns.
    @Test func settingNamesReturnsTheNamesTheyReplaced() throws {
        try twoSpeakers()
        try store.setSummary("Speaker 1 asked Speaker 2.", model: "m", for: id, labelsAtStart: [:])

        let undo = try store.setNames(
            [.remote(slot: 1): "Ann", .remote(slot: 2): "Bea"], in: id)
        #expect(undo == [.remote(slot: 1): nil, .remote(slot: 2): nil])
        #expect(try store.view(id)?.summary?.text == "Ann asked Bea.")

        let redo = try store.setNames(undo, in: id)
        #expect(redo == [.remote(slot: 1): "Ann", .remote(slot: 2): "Bea"])
        let view = try #require(try store.view(id))
        #expect(view.names.isEmpty)
        #expect(view.label(.remote(slot: 1)) == "Speaker 1")
        #expect(view.summary?.text == "Speaker 1 asked Speaker 2.")

        try store.setNames(redo, in: id)
        #expect(try store.view(id)?.summary?.text == "Ann asked Bea.")
    }

    @Test func noNameClearsTheName() throws {
        try twoSpeakers()
        try store.setNames([.remote(slot: 2): "Jane"], in: id)
        #expect(try store.setNames([.remote(slot: 2): nil], in: id) == [.remote(slot: 2): "Jane"])
        #expect(try store.view(id)?.label(.remote(slot: 2)) == "Speaker 2")
    }

    /// A speaker whose every line was given to someone else is still mentioned in the summary.
    @Test func namingASpeakerWithNoLinesLeftRenamesTheirMentions() throws {
        try twoSpeakers()
        try store.setSummary("Speaker 2 answered.", model: "m", for: id, labelsAtStart: [:])
        let second = try #require(try store.view(id)?.paragraphs.last?.id)
        try store.setEdit(ParagraphEdit(speaker: .remote(slot: 1)), of: second)

        let undo = try store.setNames([.remote(slot: 2): "Jane"], in: id)
        #expect(try store.view(id)?.summary?.text == "Jane answered.")
        try store.setNames(undo, in: id)
        #expect(try store.view(id)?.summary?.text == "Speaker 2 answered.")
    }

    /// Who spoke first stays first, even when their lines are given to someone else.
    @Test func theSpeakersAreTheOriginalOnesInOrderOfAppearance() throws {
        var transcript = final("Hello", at: 0)
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Hi", start: 2, end: 3, speaker: 2)], on: .system)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        let hi = try #require(transcript.utterances.last?.id)
        try store.setEdit(ParagraphEdit(speaker: .me), of: hi)
        #expect(try store.view(id)?.speakers == [.me, .remote(slot: 2)])
    }

    @Test func talkTimeCountsTheSpeakersLinesTheyHaveNow() throws {
        try twoSpeakers()
        let first = try #require(try store.view(id)?.paragraphs.first?.id)
        #expect(try store.view(id)?.talkTime(of: .remote(slot: 1)) == 1)
        try store.setEdit(ParagraphEdit(deleted: true), of: first)
        #expect(try store.view(id)?.talkTime(of: .remote(slot: 1)) == 0)
        #expect(try store.view(id)?.talkTime(of: .remote(slot: 2)) == 1)
    }

    /// The session being recorded is still changing; it is named once it ends.
    @Test func aTranscriptIsNamedOnlyOnceItEnds() throws {
        try store.saveLive(
            id, startedAt: started, utterances: final("Hi", speaker: 1, at: 0).utterances)
        #expect(throws: TranscriptStore.NotSealed.self) {
            try store.setNames([.remote(slot: 1): "Jane"], in: id)
        }
        #expect(try store.view(id)?.names.isEmpty == true)
    }

    @Test func aNameAnotherSpeakerHasIsRefused() throws {
        try twoSpeakers()
        try store.setNames([.remote(slot: 1): "Jane"], in: id)
        #expect(throws: SpeakerNames.InvalidName.taken(by: .remote(slot: 1))) {
            try store.setNames([.remote(slot: 2): "JANE"], in: id)
        }
        #expect(try store.view(id)?.names == [.remote(slot: 1): "Jane"])
        // Checked against the names as they will be, so two speakers can swap in one change.
        try store.setNames([.remote(slot: 1): "Bea", .remote(slot: 2): "Jane"], in: id)
        #expect(
            try store.view(id)?.names == [.remote(slot: 1): "Bea", .remote(slot: 2): "Jane"])
    }

    private func nameRecords() throws -> [SpeakerNameRecord] {
        try store.writer.read { try SpeakerNameRecord.fetchAll($0) }
    }

    /// Two Macs naming the same speaker write the same record, so a sync can merge them.
    @Test func aSpeakersNameHasTheSameRecordEverywhere() throws {
        try twoSpeakers()
        let other = try TranscriptStore.inMemory()
        try other.saveLive(
            id, startedAt: started, utterances: final("Hi", speaker: 1, at: 0).utterances)
        try other.seal(id, at: started)
        try store.setNames([.remote(slot: 1): "Jane"], in: id)
        try other.setNames([.remote(slot: 1): "Ann"], in: id)
        let ours = try nameRecords()
        let theirs = try other.writer.read { try SpeakerNameRecord.fetchAll($0) }
        #expect(ours.map(\.id) == theirs.map(\.id))
        #expect(try store.setNames([.remote(slot: 2): "Bea"], in: id).count == 1)
        #expect(Set(try nameRecords().map(\.id)).count == 2)
    }

    /// Names given before records had fixed ids keep a random one until they next change.
    @Test func aNameWithARandomRecordIsReadAndReplaced() throws {
        try twoSpeakers()
        try store.writer.write { db in
            try SpeakerNameRecord(
                id: UUID(), transcriptId: id, speaker: "remote:1", name: "Old"
            ).insert(db)
        }
        #expect(try store.view(id)?.names == [.remote(slot: 1): "Old"])

        #expect(try store.setNames([.remote(slot: 1): "New"], in: id) == [.remote(slot: 1): "Old"])
        let other = try TranscriptStore.inMemory()
        try other.saveLive(
            id, startedAt: started, utterances: final("Hi", speaker: 1, at: 0).utterances)
        try other.seal(id, at: started)
        try other.setNames([.remote(slot: 1): "New"], in: id)
        let fixed = try #require(try other.writer.read { try SpeakerNameRecord.fetchOne($0) }).id
        #expect(try nameRecords().map(\.id) == [fixed])

        // A random record read before the fixed one, as a sync from an older version could
        // leave: the fixed one is the name.
        try store.writer.write { db in
            _ = try SpeakerNameRecord.deleteAll(db)
            try SpeakerNameRecord(
                id: UUID(), transcriptId: id, speaker: "remote:1", name: "Stale"
            ).insert(db)
            try SpeakerNameRecord(
                id: fixed, transcriptId: id, speaker: "remote:1", name: "Current"
            ).insert(db)
        }
        #expect(try store.view(id)?.names == [.remote(slot: 1): "Current"])
        try store.setNames([.remote(slot: 1): nil], in: id)
        #expect(try nameRecords().isEmpty)
    }

    /// RFC 9562's example of a name-based UUID made with SHA-1.
    @Test func aNameBasedIdMatchesTheStandard() throws {
        let dns = try #require(UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
        #expect(
            UUID(v5: "www.example.com", in: dns)
                == UUID(uuidString: "2ed6657d-e927-568b-95e1-2665a8aea6a2"))
    }

    /// Named Ann and Bob, with a summary that mentions both.
    private func annAndBob(summary: String) throws {
        try twoSpeakers()
        try store.setNames([.remote(slot: 1): "Ann", .remote(slot: 2): "Bob"], in: id)
        try store.setSummary(summary, model: "m", for: id, labelsAtStart: [:])
    }

    @Test func swappingNamesSwapsTheSummarysMentions() throws {
        try annAndBob(summary: "Ann asked Bob.")
        try store.setNames([.remote(slot: 1): "Bob", .remote(slot: 2): "Ann"], in: id)
        #expect(try store.view(id)?.summary?.text == "Bob asked Ann.")
    }

    /// One speaker takes the name another gives up, in one change, and undo takes it back.
    @Test func aNamePassedOnRenamesEachMentionOnce() throws {
        try annAndBob(summary: "Ann asked Bob.")
        let undo = try store.setNames(
            [.remote(slot: 1): "Bob", .remote(slot: 2): "Cleo"], in: id)
        #expect(try store.view(id)?.summary?.text == "Bob asked Cleo.")
        try store.setNames(undo, in: id)
        #expect(try store.view(id)?.summary?.text == "Ann asked Bob.")
    }

    @Test func renamingANameInsideAnotherLeavesTheLongerOne() throws {
        try twoSpeakers()
        try store.setNames([.remote(slot: 1): "Bob", .remote(slot: 2): "Bob Smith"], in: id)
        try store.setSummary("Bob thanked Bob Smith.", model: "m", for: id, labelsAtStart: [:])
        try store.setNames([.remote(slot: 1): "Rob"], in: id)
        #expect(try store.view(id)?.summary?.text == "Rob thanked Bob Smith.")
    }

    @Test func settingTheSameNameChangesNothing() throws {
        try twoSpeakers()
        try store.setNames([.remote(slot: 1): "Ann"], in: id)
        #expect(try store.setNames([.remote(slot: 1): " Ann "], in: id).isEmpty)
    }
}

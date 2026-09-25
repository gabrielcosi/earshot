import Foundation
import GRDB
import Testing

@testable import EarshotKit

/// 0.1 kept each transcript as a Markdown file in the transcripts folder. The migration brings
/// every one into the store once, reads the files and never writes to them, and leaves the file
/// as the transcript's export only when Earshot would write exactly the same bytes.
@Suite final class TranscriptMigrationTests {
    private let store: TranscriptStore
    private let folder: URL
    private let audio: URL
    private let migration: TranscriptMigration
    /// On the minute, as a file's name records it.
    private let started = Date(timeIntervalSince1970: 1_789_999_980)

    init() throws {
        store = try TranscriptStore.inMemory()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        folder = root.appending(path: "Transcripts")
        audio = root.appending(path: "Audio")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        migration = TranscriptMigration(store: store, audioFolder: audio)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    /// A file as 0.1 wrote it, named by its start time.
    private var dated: String { MarkdownExport.filename(for: started) }

    /// Made when the session started, as 0.1 made its files, well before the migration.
    private func write(_ text: String, _ name: String) throws -> URL {
        let file = folder.appending(path: name)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.creationDate: started], ofItemAtPath: file.path(percentEncoded: false))
        return file
    }

    private func only() throws -> StoredTranscript {
        let entries = try store.list()
        try #require(entries.count == 1)
        return try #require(try store.view(entries[0].id))
    }

    /// What a file's bytes and modification date are, to show the migration left it alone.
    private func fingerprint(_ file: URL) throws -> (Data, Date?) {
        let date = try FileManager.default.attributesOfItem(
            atPath: file.path(percentEncoded: false))[.modificationDate]
        return (try Data(contentsOf: file), date as? Date)
    }

    private let untouched = """
        **Me** [00:01.00]: Hello

        **Speaker 1** [00:03.50]: Hallo
        > Hello

        """

    /// What 0.1.1's `render` and `withSummary` wrote: its own heading, a speaker the user named,
    /// a translation, and a summary.
    private var asOneWroteIt: String {
        """
        # \(MarkdownExport.title(for: started))

        ## Summary

        _Summary written by Apple Intelligence. Check it against the transcript below._

        Jane said hello.

        ---

        ## Transcript

        **Me** [00:01.00]: Hello

        **Jane** [00:03.50]: Hallo
        > Hello

        """
    }

    @Test func anUntouchedFileBecomesTheExportEarshotKeepsUpToDate() async throws {
        let file = try write(asOneWroteIt, dated)
        try await migration.run(in: folder)

        let view = try only()
        let exporter = TranscriptExporter(store: store)
        #expect(try exporter.status(of: view.id, in: folder) == .current(file))
        try store.rename(view.id, [.remote(slot: 1): "Jane Doe"])
        try exporter.export(view.id, to: folder)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Jane Doe** [00:03.50]"))
    }

    /// A file that does not come back byte for byte, such as one with the user's own notes, is
    /// theirs: the transcript starts stale and the file is never written.
    @Test func aFileEarshotWouldNotWriteTheSameStartsStale() async throws {
        let text = asOneWroteIt + "My own notes.\n"
        let file = try write(text, dated)
        try await migration.run(in: folder)

        let view = try only()
        let exporter = TranscriptExporter(store: store)
        #expect(try exporter.status(of: view.id, in: folder) == .edited(file))
        try store.rename(view.id, [.remote(slot: 1): "Jane Doe"])
        #expect(try exporter.export(view.id, to: folder) == .edited(file))
        #expect(try String(contentsOf: file, encoding: .utf8) == text)
        #expect(try store.unexported().isEmpty)
    }

    @Test func linesTranslationsTitleAndSummaryAreBroughtIn() async throws {
        _ = try write(asOneWroteIt, dated)
        try await migration.run(in: folder)

        let view = try only()
        #expect(view.title == nil)
        #expect(view.startedAt == started)
        #expect(view.paragraphs.map(\.text) == ["Hello", "Hallo"])
        #expect(view.paragraphs.map(\.start) == [1, 3.5])
        #expect(view.paragraphs.map(\.translation) == [nil, "Hello"])
        #expect(view.summary == .init(text: "Jane said hello.", model: "Apple Intelligence"))
        #expect(try store.list().first?.length == 3.5)
    }

    /// 0.1 had no way to title a transcript, so a heading of the user's own was edited in the
    /// file. It becomes the title, and since Earshot writes it back the same, the file stays the
    /// export: the edit is kept either way.
    @Test func aHeadingTheUserEditedBecomesTheTitle() async throws {
        let file = try write(
            asOneWroteIt.replacing(
                "# \(MarkdownExport.title(for: started))", with: "# Weekly sync"),
            dated)
        try await migration.run(in: folder)

        let view = try only()
        #expect(view.title == "Weekly sync")
        #expect(
            try TranscriptExporter(store: store).status(of: view.id, in: folder) == .current(file))
    }

    /// The default title is not stored: it is made from the start time, as for a live session.
    @Test func theDefaultTitleIsNotKept() async throws {
        _ = try write("# \(MarkdownExport.title(for: started))\n\n" + untouched, dated)
        try await migration.run(in: folder)
        #expect(try only().title == nil)
    }

    /// The file keeps names, not speakers: "Me" is the microphone, labels Earshot gives keep their
    /// speaker, and each name becomes a speaker of its own, numbered after those in use.
    @Test func speakerLabelsBecomeSpeakersAndNames() async throws {
        _ = try write(
            """
            # Call

            **Remote** [00:00.50]: Zero
            **Me** [00:01.00]: One
            **Speaker 1** [00:02.00]: Two
            **Jane** [00:03.00]: Three
            **Unknown speaker** [00:04.00]: Four
            **Omar** [00:05.00]: Five
            **Jane** [00:06.00]: Six

            """, dated)
        try await migration.run(in: folder)

        let view = try only()
        #expect(
            view.paragraphs.map(\.speaker) == [
                .remote(slot: 0), .me, .remote(slot: 1), .remote(slot: 2), .unknown,
                .remote(slot: 3), .remote(slot: 2),
            ])
        #expect(view.names == [.remote(slot: 2): "Jane", .remote(slot: 3): "Omar"])
        let channels = try await store.writer.read { db in
            try ParagraphRecord.order(Column("position")).fetchAll(db).map(\.channel)
        }
        #expect(channels[1] == Channel.microphone.rawValue)
        #expect(channels.enumerated().allSatisfy { $0 == 1 || $1 == Channel.system.rawValue })
    }

    /// A file the user renamed has no time in its name: it starts when the file was created.
    @Test func aRenamedFileIsBroughtInWithItsCreationDate() async throws {
        let file = try write("# Interview\n\n" + untouched, "Interview with Jane.md")
        try FileManager.default.setAttributes(
            [.creationDate: started], ofItemAtPath: file.path(percentEncoded: false))
        try await migration.run(in: folder)

        let view = try only()
        #expect(view.startedAt == started)
        #expect(view.title == "Interview")
    }

    @Test func keptAudioIsCopiedAndTheSourcesAreLeftAlone() async throws {
        let file = try write("# Call\n\n" + untouched, dated)
        let sound = folder.appending(path: dated.replacing(".md", with: ".m4a"))
        try Data("not really AAC".utf8).write(to: sound)
        let before = try (fingerprint(file), fingerprint(sound))
        try await migration.run(in: folder)

        let view = try only()
        let name = try #require(view.audio)
        #expect(try Data(contentsOf: audio.appending(path: name)) == before.1.0)
        let after = try (fingerprint(file), fingerprint(sound))
        #expect(after.0.0 == before.0.0 && after.0.1 == before.0.1)
        #expect(after.1.0 == before.1.0 && after.1.1 == before.1.1)
    }

    /// Once done, the folder is not read again: what Earshot writes there from now on is an
    /// export, not a transcript to bring in.
    @Test func aFinishedMigrationDoesNotReadTheFolderAgain() async throws {
        _ = try write("# One\n\n" + untouched, dated)
        try await migration.run(in: folder)
        _ = try write("# Later\n\n" + untouched, "Later.md")
        try await migration.run(in: folder)
        #expect(try store.list().map(\.title) == ["One"])
    }

    /// A transcript already in the store, written out by this version, is not brought in again.
    @Test func thisVersionsOwnExportsAreSkipped() async throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Hello", start: 1, end: 2, speaker: 1)],
            on: .system)
        let id = UUID()
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        try store.seal(id, at: started)
        try TranscriptExporter(store: store).export(id, to: folder)

        try await migration.run(in: folder)
        #expect(try store.list().map(\.id) == [id])
    }

    /// A file that fails, here because the audio folder cannot be made, does not stop the files
    /// after it. The run stays unfinished, and the next brings in what failed, but nothing twice,
    /// not even a file renamed in between.
    @Test func aFailedFileIsTriedAgainWithoutDuplicates() async throws {
        let first = try write("# A\n\n" + untouched, "A.md")
        _ = try write("# B\n\n" + untouched, "B.md")
        try Data("audio".utf8).write(to: folder.appending(path: "B.m4a"))
        _ = try write("# C\n\n" + untouched, "C.md")
        try Data().write(to: audio)

        await #expect(throws: (any Error).self) { try await migration.run(in: folder) }
        #expect(try Set(store.list().compactMap(\.title)) == ["A", "C"])

        try FileManager.default.removeItem(at: audio)
        try FileManager.default.moveItem(at: first, to: folder.appending(path: "A renamed.md"))
        try await migration.run(in: folder)
        #expect(try Set(store.list().compactMap(\.title)) == ["A", "B", "C"])
        #expect(try store.list().count == 3)
        let copy = try #require(
            try store.list().first { $0.title == "B" }.flatMap { try store.view($0.id)?.audio })
        #expect(
            FileManager.default.fileExists(
                atPath: audio.appending(path: copy).path(percentEncoded: false)))
    }

    /// A file that cannot be read now, such as one without permission, is not listed as
    /// unreadable for good: the next run brings it in.
    @Test func aFileThatCannotBeReadNowIsImportedLater() async throws {
        let file = try write("# Locked\n\n" + untouched, dated)
        let path = file.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        }

        await #expect(throws: (any Error).self) { try await migration.run(in: folder) }
        #expect(try store.list().isEmpty)
        #expect(try store.unimportedFiles().isEmpty)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        try await migration.run(in: folder)
        #expect(try only().title == "Locked")
    }

    /// A file that cannot be read as a transcript is listed for the user and left as it is.
    /// Other notes in the folder, which were never transcripts, are neither brought in nor listed.
    @Test func filesThatCannotBeReadAreListedAndKept() async throws {
        let empty = try write("Nothing here that looks like a line.\n", dated)
        let binary = folder.appending(path: "Garbled.md")
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: binary)
        _ = try write("# Shopping\n\n- milk\n", "Shopping.md")
        let before = try (fingerprint(empty), fingerprint(binary))
        try await migration.run(in: folder)

        #expect(try store.list().isEmpty)
        #expect(
            try Set(store.unimportedFiles().map(\.lastPathComponent))
                == [empty.lastPathComponent, binary.lastPathComponent])
        let after = try (fingerprint(empty), fingerprint(binary))
        #expect(after.0.0 == before.0.0 && after.0.1 == before.0.1)
        #expect(after.1.0 == before.1.0 && after.1.1 == before.1.1)
    }

    /// Every export this version writes is a new file, created after the migration started. An
    /// export in a folder the user left and came back to is no longer known by its path, but it
    /// is still never imported.
    @Test func exportsWrittenWhileItIsUnfinishedAreNeverImported() async throws {
        let other = folder.deletingLastPathComponent().appending(path: "Other")
        let locked = try write("# Old\n\n" + untouched, dated)
        let path = locked.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        }
        await #expect(throws: (any Error).self) { try await migration.run(in: folder) }

        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [Word(word: "New", start: 1, end: 2, speaker: 1)], on: .system)
        let id = UUID()
        try store.saveLive(id, startedAt: .now, utterances: transcript.utterances)
        try store.seal(id, at: .now)
        let exporter = TranscriptExporter(store: store)
        try exporter.export(id, to: folder)
        try await migration.run(in: other, isCurrent: { false })
        try store.rename(id, [.remote(slot: 1): "Jane"])
        try exporter.export(id, to: other)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        try await migration.run(in: folder)
        #expect(try store.list().count == 2)
        #expect(try Set(store.list().compactMap(\.title)) == ["Old"])
    }

    /// A run for a folder the user has since changed does not finish the migration, so the
    /// folder they chose is still read.
    @Test func aRunForAFolderNoLongerCurrentDoesNotFinish() async throws {
        try await migration.run(in: folder, isCurrent: { false })
        _ = try write("# Later\n\n" + untouched, "Later.md")
        try await migration.run(in: folder)
        #expect(try only().title == "Later")
    }

    @Test func noFolderMeansNothingToBringIn() async throws {
        try await migration.run(in: folder.appending(path: "Missing"))
        #expect(try store.list().isEmpty)
        #expect(try store.unimportedFiles().isEmpty)
    }
}

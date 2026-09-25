import Foundation
import Testing

@testable import EarshotKit

/// The Markdown file is a copy for the user: Earshot updates it only while it is exactly what
/// Earshot last wrote, and never writes over or brings back a file it did not write.
@Suite final class TranscriptExporterTests {
    private let store: TranscriptStore
    private let exporter: TranscriptExporter
    private let folder: URL
    private let id = UUID()
    private let started = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        store = try TranscriptStore.inMemory()
        exporter = TranscriptExporter(store: store)
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Hello", start: 1, end: 2, speaker: 1)],
            on: .system)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        try store.seal(id, at: started)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private var expectedFile: URL {
        folder.appending(path: MarkdownExport.filename(for: started))
    }

    private func contents(_ file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    @Test func theFirstExportWritesTheTranscriptsFile() throws {
        let status = try exporter.export(id, to: folder)
        #expect(status == .current(expectedFile))
        #expect(try contents(expectedFile).contains("**Speaker 1** [00:01.00]: Hello"))
        #expect(try exporter.status(of: id, in: folder) == .current(expectedFile))
    }

    @Test func anUnchangedExportFollowsTheStore() throws {
        try exporter.export(id, to: folder)
        try store.rename(id, [.remote(slot: 1): "Jane"])
        #expect(try exporter.export(id, to: folder) == .current(expectedFile))
        #expect(try contents(expectedFile).contains("**Jane** [00:01.00]: Hello"))
    }

    @Test func anExportEditedOutsideEarshotIsNeverWrittenOver() throws {
        try exporter.export(id, to: folder)
        let edited = try contents(expectedFile) + "\nMy own notes.\n"
        try edited.write(to: expectedFile, atomically: true, encoding: .utf8)

        try store.rename(id, [.remote(slot: 1): "Jane"])
        #expect(try exporter.export(id, to: folder) == .edited(expectedFile))
        #expect(try contents(expectedFile) == edited)
        #expect(try exporter.status(of: id, in: folder) == .edited(expectedFile))
    }

    @Test func aDeletedExportIsNotRecreated() throws {
        try exporter.export(id, to: folder)
        try FileManager.default.removeItem(at: expectedFile)

        #expect(try exporter.export(id, to: folder) == .missing(expectedFile))
        #expect(!FileManager.default.fileExists(atPath: expectedFile.path(percentEncoded: false)))
        #expect(try exporter.status(of: id, in: folder) == .missing(expectedFile))
    }

    @Test func aFirstExportNeverReplacesAFileAlreadyThere() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let theirs = "# A file Earshot did not write\n"
        try theirs.write(to: expectedFile, atomically: true, encoding: .utf8)

        let status = try exporter.export(id, to: folder)
        let second = folder.appending(
            path: MarkdownExport.filename(for: started).replacing(".md", with: " 2.md"))
        #expect(status == .current(second))
        #expect(try contents(expectedFile) == theirs)
        #expect(try contents(second).contains("Hello"))
    }

    /// Export… suggests a name no file has, so Return in the save panel never replaces the
    /// user's edited file or another session's.
    @Test func theSuggestedNameIsTheFirstFreeOne() throws {
        let name = MarkdownExport.filename(for: started)
        #expect(TranscriptExporter.freeFile(named: name, in: folder) == expectedFile)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: expectedFile)
        try Data().write(to: folder.appending(path: name.replacing(".md", with: " 2.md")))
        #expect(
            TranscriptExporter.freeFile(named: name, in: folder)
                == folder.appending(path: name.replacing(".md", with: " 3.md")))
    }

    @Test func twoSessionsInTheSameMinuteGetTwoFiles() throws {
        let other = UUID()
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Bye", start: 1, end: 2, speaker: 1)], on: .system)
        try store.saveLive(
            other, startedAt: started.addingTimeInterval(20), utterances: transcript.utterances)

        let first = try exporter.export(id, to: folder)
        let second = try exporter.export(other, to: folder)
        #expect(first != second)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path())
        #expect(files.count == 2)
    }

    /// A new transcripts folder gets the file from then on; the old one is left where it was.
    @Test func aNewFolderGetsItsOwnExportAndTheOldOneStays() throws {
        try exporter.export(id, to: folder)
        let old = try contents(expectedFile)
        let moved = folder.appending(path: "Moved")
        try store.rename(id, [.remote(slot: 1): "Jane"])

        let status = try exporter.export(id, to: moved)
        #expect(status == .current(moved.appending(path: MarkdownExport.filename(for: started))))
        #expect(try contents(expectedFile) == old)
        #expect(try exporter.status(of: id, in: folder) == .notExported)
    }

    /// Export… writes a copy where the user chose; one in the transcripts folder becomes the file
    /// Earshot keeps up to date, so a stale export can be replaced.
    @Test func aCopySavedInTheFolderBecomesTheExport() throws {
        try exporter.export(id, to: folder)
        try "edited".write(to: expectedFile, atomically: true, encoding: .utf8)
        let copy = folder.appending(path: "Copy.md")

        try exporter.saveCopy(id, to: copy, folder: folder)
        #expect(try exporter.status(of: id, in: folder) == .current(copy))
        #expect(try contents(expectedFile) == "edited")
        try store.rename(id, [.remote(slot: 1): "Jane"])
        #expect(try exporter.export(id, to: folder) == .current(copy))
        #expect(try contents(copy).contains("**Jane**"))
    }

    @Test func aCopySavedElsewhereLeavesTheExportAlone() throws {
        try exporter.export(id, to: folder)
        let elsewhere = folder.appending(path: "Elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try exporter.saveCopy(id, to: elsewhere.appending(path: "Copy.md"), folder: folder)
        #expect(try exporter.status(of: id, in: folder) == .current(expectedFile))
    }

    @Test func wordRulesApplyWhenTheFileIsWritten() throws {
        var rules = WordRules()
        rules.replacements = [WordRules.Replacement(pattern: "Hello", replacement: "Howdy")]
        try exporter.export(id, to: folder, rules: rules)
        #expect(try contents(expectedFile).contains("]: Howdy"))
        #expect(try store.view(id)?.paragraphs.first?.text == "Hello")
    }

    /// Files are written as 0.1 wrote them, so the migration can tell an untouched one.
    @Test func theFileHasTheSameFormatAsBefore() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "",
            words: [
                Word(word: "Hallo", start: 1, end: 2, speaker: 1),
                Word(word: "Hi", start: 3, end: 4, speaker: 2),
            ], on: .system)
        let other = UUID()
        try store.saveLive(other, startedAt: started, utterances: transcript.utterances)
        try store.setTranslation(
            "Hello", of: "Hallo", language: "en", for: transcript.utterances[0].id)
        try store.rename(other, [.remote(slot: 2): "Jane"])
        try store.setSummary("Jane said hi.", model: "m", for: other, labelsAtStart: [:])

        // As 0.1 wrote it: the title, the summary above a rule, then each line with its time to
        // the hundredth and its translation quoted under it.
        let expected = """
            # \(MarkdownExport.title(for: started))

            ## Summary

            _Summary written by m. Check it against the transcript below._

            Jane said hi.

            ---

            ## Transcript

            **Speaker 1** [00:01.00]: Hallo
            > Hello

            **Jane** [00:03.00]: Hi

            """
        #expect(try store.view(other)?.markdown() == expected)
    }
}

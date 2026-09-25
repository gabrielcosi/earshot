import CryptoKit
import Foundation
import GRDB

/// Brings the transcripts Earshot 0.1 kept as Markdown files in the transcripts folder into the
/// store, once. The files are only read: nothing is written to, moved, or deleted from the folder.
public struct TranscriptMigration: Sendable {
    let store: TranscriptStore
    let audioFolder: URL

    public init(store: TranscriptStore, audioFolder: URL) {
        self.store = store
        self.audioFolder = audioFolder
    }

    /// Brings in each file in `folder` not brought in yet, each in a transaction of its own, so a
    /// run cut short resumes where it stopped. A file that fails does not stop the others; the
    /// run then throws the first failure and stays unfinished, so the next run tries it again. A
    /// run in which every file succeeds finishes the migration, and the folder is not read for
    /// it again: what lands there from then on is Earshot's own exports and the user's files.
    /// Files created after the first run started are left out on every run, since every export
    /// this version writes is a new file, and an export in a folder the user left and came back
    /// to is no longer known by its path. `progress` hears how many of the folder's files are
    /// done after each one; `isCurrent` says whether `folder` is still the transcripts folder,
    /// and a run for one that no longer is does not finish the migration.
    public func run(
        in folder: URL, progress: @Sendable (_ done: Int, _ total: Int) async -> Void = { _, _ in },
        isCurrent: @Sendable () async -> Bool = { true }
    ) async throws {
        guard let started = try store.startMigration() else { return }
        let files = try Self.markdownFiles(in: folder)
        var failure: (any Error)?
        for (index, file) in files.enumerated() {
            do {
                try bringIn(file, before: started)
            } catch {
                failure = failure ?? error
            }
            await progress(index + 1, files.count)
        }
        if let failure { throw failure }
        guard await isCurrent() else { return }
        try store.finishMigration()
    }

    /// Named within `folder` as given, as exports are, rather than as the listing resolves it.
    private static func markdownFiles(in folder: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                atPath: folder.path(percentEncoded: false)
            )
            .filter { !$0.hasPrefix(".") && ($0 as NSString).pathExtension.lowercased() == "md" }
            .sorted().map { folder.appending(path: $0) }
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    /// A file is brought in unless the store knows it already: by its path, or by its contents,
    /// so a file renamed between two runs is not brought in twice; a file this version exported
    /// is known the same way. Every `.md` with at least one transcript line is a transcript,
    /// whatever its name. One that is not UTF-8 text, or is named as Earshot names its files and
    /// holds no line, is listed for the user; other notes in the folder are left out quietly. A
    /// file that cannot be read at all throws, so it is tried again.
    private func bringIn(_ file: URL, before started: Date) throws {
        let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate
        guard (created ?? .distantPast) <= started else { return }
        let path = file.path(percentEncoded: false)
        let data = try Data(contentsOf: file)
        let sha256 = TranscriptStore.hash(data)
        guard try !store.migrationKnows(path: path, sha256: sha256) else { return }
        guard let markdown = String(data: data, encoding: .utf8) else {
            return try store.recordUnimported(path)
        }
        let document = TranscriptDocument(markdown: markdown)
        let name = file.lastPathComponent
        let dated = MarkdownExport.date(fromFilename: name)
        guard !document.lines.isEmpty else {
            if dated != nil { try store.recordUnimported(path) }
            return
        }
        let title: String? =
            if document.title.isEmpty {
                dated == nil ? file.deletingPathExtension().lastPathComponent : nil
            } else if MarkdownExport.hasDefaultTitle(document.title, filename: name) {
                nil
            } else {
                document.title
            }
        var source = Source(
            id: Self.id(for: sha256), path: path, sha256: sha256, document: document, title: title,
            startedAt: dated ?? created ?? .now)
        source.audio = try copyAudio(of: file, as: source.id)
        try store.importTranscript(source)
    }

    /// A file to store as a transcript, and what was worked out from it.
    struct Source {
        let id: UUID
        let path: String
        let sha256: String
        let document: TranscriptDocument
        let title: String?
        let startedAt: Date
        var audio: String?
    }

    /// 0.1 kept a session's audio next to its file, under the same name. The copy is named by the
    /// transcript, which is named by the file's contents, so a run cut short between the copy and
    /// the import replaces its own copy when it resumes instead of leaving one behind.
    private func copyAudio(of file: URL, as id: UUID) throws -> String? {
        let source = file.deletingPathExtension().appendingPathExtension("m4a")
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            return nil
        }
        let name = "\(id.uuidString).m4a"
        let destination = audioFolder.appending(path: name)
        try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        return name
    }

    /// A version 8 UUID made from the file's SHA-256.
    private static func id(for sha256: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(sha256.utf8)).prefix(16))
        bytes[6] = bytes[6] & 0x0F | 0x80
        bytes[8] = bytes[8] & 0x3F | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    /// The file keeps labels, not speakers. "Me" is the microphone, since naming never renamed
    /// it; a label Earshot gives, such as "Speaker 2", is that speaker; and each other label is a
    /// named speaker, given a number no label uses, in order of first appearance.
    static func speakers(of labels: [String]) -> (
        speakers: [String: Speaker], names: [Speaker: String]
    ) {
        var speakers: [String: Speaker] = [:]
        for label in labels {
            let number = label.firstMatch(of: /^Speaker (\d+)$/).flatMap { Int($0.output.1) }
            let candidates: [Speaker] = [.me, .unknown, .remote(slot: number ?? 0)]
            speakers[label] = candidates.first { $0.label == label }
        }
        var names: [Speaker: String] = [:]
        var slot = 1
        for label in labels where speakers[label] == nil {
            while speakers.values.contains(.remote(slot: slot)) { slot += 1 }
            speakers[label] = .remote(slot: slot)
            names[.remote(slot: slot)] = label
        }
        return (speakers, names)
    }
}

/// A file the migration brought in, or could not read. A path means nothing on another Mac, so
/// this table is never synced.
struct MigratedFileRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_migration_file"
    var id: UUID
    var path: String
    var sha256: String?
    var transcriptId: UUID?
    var imported: Bool
}

/// When this Mac started bringing in 0.1's files, and when it finished; never synced.
struct MigrationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_migration"
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
}

extension TranscriptStore {
    /// Files in the transcripts folder the migration could not read as transcripts. They are left
    /// where they are.
    public func unimportedFiles() throws -> [URL] {
        try writer.read { db in
            try MigratedFileRecord.filter(Column("imported") == false).fetchAll(db)
                .map { URL(filePath: $0.path) }
        }
    }

    /// When the first run started, recorded now if this is it; nil once the migration finished.
    func startMigration() throws -> Date? {
        try writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM local_migration") else {
                let record = MigrationRecord(id: UUID(), startedAt: .now)
                try record.insert(db)
                return record.startedAt
            }
            let finished: Date? = row["finishedAt"]
            return finished == nil ? row["startedAt"] : nil
        }
    }

    func finishMigration() throws {
        try writer.write { db in
            _ = try MigrationRecord.updateAll(db, Column("finishedAt").set(to: Date.now))
        }
    }

    func migrationKnows(path: String, sha256: String) throws -> Bool {
        try writer.read { db in
            if try MigratedFileRecord.filter(Column("path") == path).fetchCount(db) > 0
                || ExportRecord.filter(Column("path") == path).fetchCount(db) > 0
            {
                return true
            }
            return try MigratedFileRecord.filter(Column("sha256") == sha256).fetchCount(db) > 0
                || ExportRecord.filter(Column("sha256") == sha256).fetchCount(db) > 0
        }
    }

    func recordUnimported(_ path: String) throws {
        try writer.write { db in
            try MigratedFileRecord(id: UUID(), path: path, imported: false).insert(db)
        }
    }

    /// Stores a 0.1 file as a transcript, in one transaction with the record that it was brought
    /// in. Paragraph ends were not kept, so each ends where it starts, and the transcript where
    /// its last paragraph starts, as 0.1 measured it. The export is recorded as what Earshot would
    /// write: a file that is exactly that stays the export Earshot keeps up to date, and any other
    /// is the user's, reads as changed outside Earshot, and is never written over.
    func importTranscript(_ source: TranscriptMigration.Source) throws {
        let (id, document) = (source.id, source.document)
        let (speakers, names) = TranscriptMigration.speakers(of: document.lines.map(\.label))
        try writer.write { db in
            try TranscriptRecord(
                id: id, startedAt: source.startedAt,
                endedAt: source.startedAt.addingTimeInterval(document.lines.last?.start ?? 0),
                title: source.title, origin: "imported", audio: source.audio
            ).insert(db)
            for (position, line) in document.lines.enumerated() {
                let speaker = speakers[line.label] ?? .unknown
                let paragraph = ParagraphRecord(
                    id: UUID(), transcriptId: id, position: position,
                    channel: (speaker == .me ? Channel.microphone : .system).rawValue,
                    speaker: speaker.key, start: line.start, end: line.start, text: line.text,
                    words: [])
                try paragraph.insert(db)
                if let translation = line.translation {
                    try TranslationRecord(
                        id: UUID(), paragraphId: paragraph.id, sourceHash: Self.hash(line.text),
                        language: "", text: translation, createdAt: .now
                    ).insert(db)
                }
            }
            for (speaker, name) in names {
                try SpeakerNameRecord(
                    id: UUID(), transcriptId: id, speaker: speaker.key, name: name
                ).insert(db)
            }
            if let summary = document.summary {
                try SummaryRecord(
                    id: UUID(), transcriptId: id, text: summary.text, model: summary.model,
                    createdAt: .now
                ).insert(db)
            }
            let rendered = try Self.view(id, in: db)?.markdown() ?? ""
            try ExportRecord(
                id: UUID(), transcriptId: id, path: source.path, sha256: Self.hash(rendered),
                exportedAt: .now
            ).insert(db)
            try MigratedFileRecord(
                id: UUID(), path: source.path, sha256: source.sha256, transcriptId: id,
                imported: true
            ).insert(db)
        }
    }
}

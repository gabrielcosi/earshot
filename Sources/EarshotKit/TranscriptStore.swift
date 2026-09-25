import CryptoKit
import Foundation
import GRDB

/// Every transcript, in one SQLite database: the source of truth. What was heard is stored as it
/// was heard; names, edits, translations, and the summary sit beside it, and the Markdown file is
/// a copy written from here.
public final class TranscriptStore: Sendable {
    let writer: any DatabaseWriter

    /// A transcript in the list.
    public struct Entry: Identifiable, Sendable, Equatable {
        public let id: UUID
        /// The user's title; nil while it has Earshot's own, made from the time.
        public let title: String?
        public let startedAt: Date
        /// Where the last paragraph ends.
        public let length: Double?
    }

    /// Opens the store and brings its schema up to date.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The app's store. A pool lets the window read while a session writes.
    public static func open(at file: URL) throws -> TranscriptStore {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try TranscriptStore(DatabasePool(path: file.path(percentEncoded: false)))
    }

    public static func inMemory() throws -> TranscriptStore {
        try TranscriptStore(DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1") { db in
            try db.create(table: "transcript") { table in
                table.primaryKey("id", .blob)
                table.column("startedAt", .datetime).notNull()
                table.column("endedAt", .datetime)
                table.column("title", .text)
                table.column("origin", .text).notNull().defaults(to: "live")
                table.column("audio", .text)
            }
            try db.create(table: "paragraph") { table in
                table.primaryKey("id", .blob)
                table.column("transcriptId", .blob).notNull().indexed()
                    .references("transcript", onDelete: .cascade)
                table.column("position", .integer).notNull()
                table.column("channel", .text).notNull()
                table.column("speaker", .text).notNull()
                table.column("start", .double).notNull()
                table.column("end", .double).notNull()
                table.column("text", .text).notNull()
                table.column("words", .jsonText).notNull().defaults(to: "[]")
                table.column("language", .text)
            }
            try db.create(table: "paragraph_edit") { table in
                table.primaryKey("id", .blob)
                table.column("paragraphId", .blob).notNull().indexed()
                    .references("paragraph", onDelete: .cascade)
                table.column("text", .text)
                table.column("speaker", .text)
                table.column("deleted", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "speaker_name") { table in
                table.primaryKey("id", .blob)
                table.column("transcriptId", .blob).notNull().indexed()
                    .references("transcript", onDelete: .cascade)
                table.column("speaker", .text).notNull()
                table.column("name", .text).notNull()
            }
            try db.create(table: "translation") { table in
                table.primaryKey("id", .blob)
                table.column("paragraphId", .blob).notNull().indexed()
                    .references("paragraph", onDelete: .cascade)
                table.column("sourceHash", .text).notNull()
                table.column("language", .text).notNull()
                table.column("text", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "summary") { table in
                table.primaryKey("id", .blob)
                table.column("transcriptId", .blob).notNull().indexed()
                    .references("transcript", onDelete: .cascade)
                table.column("text", .text).notNull()
                table.column("model", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "local_export") { table in
                table.primaryKey("id", .blob)
                table.column("transcriptId", .blob).notNull().indexed()
                    .references("transcript", onDelete: .cascade)
                table.column("path", .text).notNull()
                table.column("sha256", .text).notNull()
                table.column("exportedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "local_migration") { table in
                table.primaryKey("id", .blob)
                table.column("startedAt", .datetime).notNull()
                table.column("finishedAt", .datetime)
            }
            try db.create(table: "local_migration_file") { table in
                table.primaryKey("id", .blob)
                table.column("path", .text).notNull()
                table.column("sha256", .text)
                table.column("transcriptId", .blob).indexed()
                    .references("transcript", onDelete: .setNull)
                table.column("imported", .boolean).notNull()
            }
        }
        return migrator
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ text: String) -> String { hash(Data(text.utf8)) }
}

// MARK: - The session being recorded

extension TranscriptStore {
    /// Writes the session's paragraphs as they are now, in one transaction: those that differ
    /// from `previous`, what the last save wrote, and none that are gone. Paragraphs `previous`
    /// already holds unchanged are not written again: an hour holds some ten thousand timed words,
    /// and each final changes one paragraph. The transcript is created with its first paragraph,
    /// so a session in which nothing was said leaves nothing behind. A sealed transcript's
    /// paragraphs are the original and do not change.
    public func saveLive(
        _ transcript: UUID, startedAt: Date, utterances: [Utterance], previous: [Utterance] = []
    ) throws {
        guard !utterances.isEmpty else { return }
        try writer.write { db in
            if let existing = try TranscriptRecord.fetchOne(db, key: transcript) {
                guard existing.endedAt == nil else { return }
            } else {
                try TranscriptRecord(id: transcript, startedAt: startedAt, origin: "live")
                    .insert(db)
            }
            for (position, utterance) in utterances.enumerated()
            where !previous.indices.contains(position) || previous[position] != utterance {
                try ParagraphRecord(
                    id: utterance.id, transcriptId: transcript, position: position,
                    channel: (utterance.speaker == .me ? Channel.microphone : .system).rawValue,
                    speaker: utterance.speaker.key, start: utterance.start, end: utterance.end,
                    text: utterance.text, words: utterance.segments.flatMap(\.words)
                ).upsert(db)
            }
            try ParagraphRecord.filter(Column("transcriptId") == transcript)
                .filter(!utterances.map(\.id).contains(Column("id"))).deleteAll(db)
        }
    }

    /// Keeps one translation per paragraph. One for a paragraph that is gone, replaced by
    /// relabelling while it was being made, is dropped.
    public func setTranslation(
        _ text: String, of source: String, language: String, for paragraph: UUID
    ) throws {
        try writer.write { db in
            guard try ParagraphRecord.exists(db, key: paragraph) else { return }
            var record =
                try TranslationRecord.filter(Column("paragraphId") == paragraph).fetchOne(db)
                ?? TranslationRecord(
                    id: UUID(), paragraphId: paragraph, sourceHash: "", language: "", text: "",
                    createdAt: .now)
            record.sourceHash = Self.hash(source)
            record.language = language
            record.text = text
            record.createdAt = .now
            try record.upsert(db)
        }
    }

    /// Marks the session over: from here its paragraphs are the original.
    public func seal(_ transcript: UUID, at date: Date) throws {
        try writer.write { db in
            _ = try TranscriptRecord.filter(key: transcript)
                .updateAll(db, Column("endedAt").set(to: date))
        }
    }

    /// Transcripts a crash or a forced quit left open, sealed where their last paragraph ends.
    public func sealUnfinished() throws -> [UUID] {
        try writer.write { db in
            let open = try TranscriptRecord.filter(Column("endedAt") == nil).fetchAll(db)
            for var transcript in open {
                let end = try Double.fetchOne(
                    db, sql: #"SELECT MAX("end") FROM paragraph WHERE transcriptId = ?"#,
                    arguments: [transcript.id])
                transcript.endedAt = transcript.startedAt.addingTimeInterval(end ?? 0)
                try transcript.update(db)
            }
            return open.map(\.id)
        }
    }

    public func setAudio(_ name: String?, for transcript: UUID) throws {
        try writer.write { db in
            _ = try TranscriptRecord.filter(key: transcript)
                .updateAll(db, Column("audio").set(to: name))
        }
    }
}

// MARK: - Reading

extension TranscriptStore {
    /// Newest first.
    public func list() throws -> [Entry] {
        try writer.read(Self.list)
    }

    /// The list now and after every change, for the sidebar.
    public func listChanges() -> some AsyncSequence<[Entry], any Error> {
        ValueObservation.tracking(Self.list).values(in: writer)
    }

    /// The transcript now and after every change to it, for the window.
    public func viewChanges(_ transcript: UUID) -> some AsyncSequence<StoredTranscript?, any Error>
    {
        ValueObservation.tracking { try Self.view(transcript, in: $0) }.removeDuplicates()
            .values(in: writer)
    }

    static func list(_ db: Database) throws -> [Entry] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT id, title, startedAt,
                    (SELECT MAX("end") FROM paragraph WHERE transcriptId = transcript.id) AS length
                FROM transcript ORDER BY startedAt DESC
                """
        ).map { row in
            Entry(
                id: row["id"], title: row["title"], startedAt: row["startedAt"],
                length: row["length"])
        }
    }

    /// The transcript as it reads now: the original with its edits, names, translations, and
    /// summary. Nil when there is no such transcript.
    public func view(_ transcript: UUID) throws -> StoredTranscript? {
        try writer.read { try Self.view(transcript, in: $0) }
    }

    static func view(_ id: UUID, in db: Database) throws -> StoredTranscript? {
        guard let transcript = try TranscriptRecord.fetchOne(db, key: id) else { return nil }
        let paragraphs = try ParagraphRecord.filter(Column("transcriptId") == id)
            .order(Column("position")).fetchAll(db)
        let ids = paragraphs.map(\.id)
        let edits = Dictionary(
            try ParagraphEditRecord.filter(ids.contains(Column("paragraphId"))).fetchAll(db)
                .map { ($0.paragraphId, $0) }, uniquingKeysWith: { first, _ in first })
        let translations = Dictionary(
            try TranslationRecord.filter(ids.contains(Column("paragraphId")))
                .order(Column("createdAt")).fetchAll(db).map { ($0.paragraphId, $0) },
            uniquingKeysWith: { _, last in last })
        // A name with a random id, from before ids were fixed, gives way to one with the fixed id.
        var names: [Speaker: SpeakerNameRecord] = [:]
        for record in try SpeakerNameRecord.filter(Column("transcriptId") == id).fetchAll(db) {
            guard let speaker = Speaker(key: record.speaker),
                names[speaker] == nil
                    || record.id == SpeakerNameRecord.id(of: record.speaker, in: id)
            else { continue }
            names[speaker] = record
        }
        let summary = try SummaryRecord.filter(Column("transcriptId") == id).fetchOne(db)
        return StoredTranscript(
            id: id, startedAt: transcript.startedAt, endedAt: transcript.endedAt,
            title: transcript.title, audio: transcript.audio,
            paragraphs: paragraphs.compactMap { paragraph in
                let edit = edits[paragraph.id]
                guard edit?.deleted != true else { return nil }
                let text = edit?.text ?? paragraph.text
                let translation = translations[paragraph.id]
                return StoredTranscript.Paragraph(
                    id: paragraph.id,
                    speaker: Speaker(key: edit?.speaker ?? paragraph.speaker) ?? .unknown,
                    start: paragraph.start, end: paragraph.end, text: text,
                    translation: translation?.sourceHash == hash(text) ? translation?.text : nil)
            },
            speakers: paragraphs.reduce(into: []) { speakers, paragraph in
                let speaker = Speaker(key: paragraph.speaker) ?? .unknown
                if !speakers.contains(speaker) { speakers.append(speaker) }
            },
            names: names.mapValues(\.name),
            summary: summary.map { TranscriptDocument.Summary(text: $0.text, model: $0.model) })
    }

    /// Sealed transcripts never written to a file: the session's export did not finish, or the
    /// session ended in a crash.
    public func unexported() throws -> [UUID] {
        try writer.read { db in
            try UUID.fetchAll(
                db,
                sql: """
                    SELECT id FROM transcript WHERE endedAt IS NOT NULL
                    AND id NOT IN (SELECT transcriptId FROM local_export)
                    """)
        }
    }
}

import Foundation
import GRDB

// MARK: - The title

extension TranscriptStore {
    /// Gives the transcript a title, stored as one trimmed line: the Markdown file's heading is
    /// `# title`, and a line break in it would add lines the migration reads as transcript lines.
    /// An empty title gives back Earshot's own, made from the time. Returns the title it had, for
    /// undo, or nil when nothing changed or there is no such transcript.
    @discardableResult
    public func setTitle(_ title: String?, of transcript: UUID) throws -> String?? {
        let title = title.map {
            $0.split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        let new = title?.isEmpty == false ? title : nil
        return try writer.write { db in
            guard var record = try TranscriptRecord.fetchOne(db, key: transcript),
                record.title != new
            else { return nil }
            let previous = record.title
            record.title = new
            try record.update(db)
            return .some(previous)
        }
    }
}

// MARK: - Deleting

/// Kept audio of a deleted transcript whose file is still to be removed. A file name means
/// nothing on another Mac, so this table is never synced.
struct PendingRemovalRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_pending_removal"
    var id: UUID
    var name: String
}

extension TranscriptStore {
    /// Deletes the transcripts and everything they hold, and records their kept audio to be
    /// removed, in one transaction: a crash before the files are gone leaves their names, not
    /// files nothing knows about. Returns the file names, as the store has them.
    @discardableResult
    public func delete(_ transcripts: Set<UUID>) throws -> [String] {
        try writer.write { db in
            let records = try TranscriptRecord.filter(keys: transcripts).fetchAll(db)
            _ = try TranscriptRecord.deleteAll(db, keys: transcripts)
            let audio = records.compactMap(\.audio)
            for name in audio { try PendingRemovalRecord(id: UUID(), name: name).insert(db) }
            return audio
        }
    }

    /// Removes the kept audio of deleted transcripts from `folder`, each name once its file is
    /// gone, and returns the names. Run after a delete, and at launch for any a crash or a failed
    /// removal left. Only those files: audio the store has no transcript for but never deleted,
    /// such as audio kept while the store could not be opened, is not Earshot's to remove.
    public func removeDeletedAudio(in folder: URL) throws -> [String] {
        let pending = try writer.read { try PendingRemovalRecord.fetchAll($0) }
        for record in pending {
            do {
                try FileManager.default.removeItem(at: folder.appending(path: record.name))
            } catch CocoaError.fileNoSuchFile {
                // Already gone: nothing is left to remove.
            }
            _ = try writer.write { try record.delete($0) }
        }
        return pending.map(\.name).sorted()
    }
}

// MARK: - Names and the summary

extension TranscriptStore {
    /// The session being recorded is still changing, so it is named once it ends.
    public struct NotSealed: Error {}

    /// Names speakers, nil giving one back their label, and writes the new names over the old
    /// ones wherever the summary mentions them. Every name is checked against the names as they
    /// will be, so two speakers can swap names in one change, and nothing is written when one is
    /// invalid. Returns the names the changed speakers had: setting them back undoes the change.
    @discardableResult
    public func setNames(_ names: [Speaker: String?], in transcript: UUID) throws -> [Speaker:
        String?]
    {
        try writer.write { db in
            guard let before = try Self.view(transcript, in: db) else { return [:] }
            guard before.endedAt != nil else { throw NotSealed() }
            var after = before.names
            for (speaker, name) in names {
                after[speaker] = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            after = after.filter { !$0.value.isEmpty }
            for speaker in names.keys {
                if let name = after[speaker] {
                    after[speaker] = try SpeakerNames.validate(name, for: speaker, names: after)
                }
            }
            var previous: [Speaker: String?] = [:]
            for speaker in names.keys where before.names[speaker] != after[speaker] {
                previous.updateValue(before.names[speaker], forKey: speaker)
                let id = SpeakerNameRecord.id(of: speaker.key, in: transcript)
                try SpeakerNameRecord.filter(Column("transcriptId") == transcript)
                    .filter(Column("speaker") == speaker.key).filter(Column("id") != id)
                    .deleteAll(db)
                if let name = after[speaker] {
                    try SpeakerNameRecord(
                        id: id, transcriptId: transcript, speaker: speaker.key, name: name
                    ).upsert(db)
                } else {
                    try SpeakerNameRecord.deleteOne(db, key: id)
                }
            }
            try Self.updateSummaryLabels(transcript, from: before.labels, in: db)
            return previous
        }
    }

    /// Stores a summary that was started with `labelsAtStart`. A summary takes up to a minute,
    /// so the speakers may have been renamed meanwhile: it is brought up to the names as they
    /// are when it is written, and nothing else in the store is touched. False when the
    /// transcript was deleted meanwhile, and there is nothing to store it with.
    @discardableResult
    public func setSummary(
        _ text: String, model: String, for transcript: UUID, labelsAtStart: [Speaker: String]
    ) throws -> Bool {
        try writer.write { db in
            guard try TranscriptRecord.exists(db, key: transcript) else { return false }
            var record =
                try SummaryRecord.filter(Column("transcriptId") == transcript).fetchOne(db)
                ?? SummaryRecord(
                    id: UUID(), transcriptId: transcript, text: "", model: "", createdAt: .now)
            record.text = text
            record.model = model
            record.createdAt = .now
            try record.upsert(db)
            try Self.updateSummaryLabels(transcript, from: labelsAtStart, in: db)
            return true
        }
    }

    private static func updateSummaryLabels(
        _ transcript: UUID, from old: [Speaker: String], in db: Database
    ) throws {
        guard let now = try view(transcript, in: db)?.labels,
            var summary = try SummaryRecord.filter(Column("transcriptId") == transcript)
                .fetchOne(db)
        else { return }
        var renamed: [String: String] = [:]
        for (speaker, label) in old { renamed[label] = now[speaker] ?? label }
        guard renamed.contains(where: { $0.key != $0.value }) else { return }
        summary.text = SpeakerNames.renameMentions(in: summary.text, renamed)
        try summary.update(db)
    }
}

// MARK: - Edits

extension TranscriptStore {
    public func edit(of paragraph: UUID) throws -> ParagraphEdit? {
        try writer.read { db in
            try ParagraphEditRecord.filter(Column("paragraphId") == paragraph).fetchOne(db)
                .map(Self.edit)
        }
    }

    /// Replaces the paragraph's edit; nil, or an edit that changes nothing, shows the original
    /// again. Undo sets back the edit this replaced.
    public func setEdit(_ edit: ParagraphEdit?, of paragraph: UUID) throws {
        try writer.write { db in
            let existing = try ParagraphEditRecord.filter(Column("paragraphId") == paragraph)
                .fetchOne(db)
            guard let edit, !edit.isEmpty else {
                try existing?.delete(db)
                return
            }
            var record =
                existing
                ?? ParagraphEditRecord(
                    id: UUID(), paragraphId: paragraph, text: nil, speaker: nil, deleted: false)
            record.text = edit.text
            record.speaker = edit.speaker?.key
            record.deleted = edit.deleted
            try record.upsert(db)
        }
    }

    /// Removes every edit in the transcript, and returns them by paragraph so undo can put them
    /// back.
    public func revertEdits(in transcript: UUID) throws -> [UUID: ParagraphEdit] {
        try writer.write { db in
            let edits = try ParagraphEditRecord.filter(
                sql: "paragraphId IN (SELECT id FROM paragraph WHERE transcriptId = ?)",
                arguments: [transcript]
            ).fetchAll(db)
            for edit in edits { try edit.delete(db) }
            return Dictionary(
                edits.map { ($0.paragraphId, Self.edit($0)) },
                uniquingKeysWith: { first, _ in first })
        }
    }

    private static func edit(_ record: ParagraphEditRecord) -> ParagraphEdit {
        ParagraphEdit(
            text: record.text, speaker: record.speaker.flatMap(Speaker.init(key:)),
            deleted: record.deleted)
    }
}

// MARK: - This Mac's export

extension TranscriptStore {
    func exportRecord(of transcript: UUID) throws -> ExportRecord? {
        try writer.read { db in
            try ExportRecord.filter(Column("transcriptId") == transcript).fetchOne(db)
        }
    }

    /// Remembers the file Earshot wrote and what was in it, which is what keeps it from ever
    /// writing over a change made outside Earshot.
    func recordExport(of transcript: UUID, at file: URL, contents: Data) throws {
        try writer.write { db in
            var record =
                try ExportRecord.filter(Column("transcriptId") == transcript).fetchOne(db)
                ?? ExportRecord(
                    id: UUID(), transcriptId: transcript, path: "", sha256: "", exportedAt: .now)
            record.path = file.path(percentEncoded: false)
            record.sha256 = Self.hash(contents)
            record.exportedAt = .now
            try record.upsert(db)
        }
    }
}

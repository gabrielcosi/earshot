import Foundation
import GRDB

// MARK: - Names and the summary

extension TranscriptStore {
    /// Names speakers, and writes the new names over the old labels wherever the summary mentions
    /// them. An empty name leaves the speaker as they were.
    public func rename(_ transcript: UUID, _ names: [Speaker: String]) throws {
        try writer.write { db in
            guard let before = try Self.view(transcript, in: db) else { return }
            for (speaker, name) in names {
                let name = name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                var record =
                    try SpeakerNameRecord.filter(Column("transcriptId") == transcript)
                    .filter(Column("speaker") == speaker.key).fetchOne(db)
                    ?? SpeakerNameRecord(
                        id: UUID(), transcriptId: transcript, speaker: speaker.key, name: name)
                record.name = name
                try record.upsert(db)
            }
            try Self.updateSummaryLabels(transcript, from: before.labels, in: db)
        }
    }

    /// Stores a summary that was started with `labelsAtStart`. A summary takes up to a minute,
    /// so the speakers may have been renamed meanwhile: it is brought up to the names as they
    /// are when it is written, and nothing else in the store is touched.
    public func setSummary(
        _ text: String, model: String, for transcript: UUID, labelsAtStart: [Speaker: String]
    ) throws {
        try writer.write { db in
            guard try TranscriptRecord.exists(db, key: transcript) else { return }
            var record =
                try SummaryRecord.filter(Column("transcriptId") == transcript).fetchOne(db)
                ?? SummaryRecord(
                    id: UUID(), transcriptId: transcript, text: "", model: "", createdAt: .now)
            record.text = text
            record.model = model
            record.createdAt = .now
            try record.upsert(db)
            try Self.updateSummaryLabels(transcript, from: labelsAtStart, in: db)
        }
    }

    private static func updateSummaryLabels(
        _ transcript: UUID, from old: [Speaker: String], in db: Database
    ) throws {
        guard let now = try view(transcript, in: db)?.labels,
            var summary = try SummaryRecord.filter(Column("transcriptId") == transcript)
                .fetchOne(db)
        else { return }
        var changed: [String: String] = [:]
        for (speaker, label) in old where now[speaker].map({ $0 != label }) == true {
            changed[label] = now[speaker]
        }
        guard !changed.isEmpty else { return }
        summary.text = SpeakerNames.renameMentions(in: summary.text, changed)
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

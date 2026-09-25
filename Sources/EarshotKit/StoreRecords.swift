import Foundation
import GRDB

/// The store's rows. Every table has a UUID key of its own and no other unique constraint, so the
/// rows can become CloudKit records when sync comes: CloudKit names records by one ID and enforces
/// nothing else. Foreign keys cascade, and columns added later must be nullable or have a default.
struct TranscriptRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcript"
    var id: UUID
    var startedAt: Date
    /// Nil while the session is being recorded, or when it ended in a crash and was not sealed yet.
    var endedAt: Date?
    /// The user's title; nil for the one Earshot gives, which is made from `startedAt`.
    var title: String?
    /// `live` for a session Earshot recorded; the migration of older files adds `imported`.
    var origin: String
    /// The kept audio's file name in the store's audio folder.
    var audio: String?
}

/// A paragraph as it was heard: the original, which edits never change.
struct ParagraphRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "paragraph"
    var id: UUID
    var transcriptId: UUID
    var position: Int
    var channel: String
    var speaker: String
    var start: Double
    var end: Double
    var text: String
    var words: [Word]
    var language: String?
}

/// The user's changes to one paragraph, as its current state rather than a history.
struct ParagraphEditRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "paragraph_edit"
    var id: UUID
    var paragraphId: UUID
    var text: String?
    var speaker: String?
    var deleted: Bool
}

struct SpeakerNameRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "speaker_name"
    var id: UUID
    var transcriptId: UUID
    var speaker: String
    var name: String
}

/// A paragraph's translation, current only while the paragraph's text hashes to `sourceHash`.
struct TranslationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "translation"
    var id: UUID
    var paragraphId: UUID
    var sourceHash: String
    var language: String
    var text: String
    var createdAt: Date
}

/// Only the latest summary is kept.
struct SummaryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "summary"
    var id: UUID
    var transcriptId: UUID
    var text: String
    var model: String
    var createdAt: Date
}

/// Where this Mac exported a transcript, and the hash of what it wrote. A path means nothing on
/// another Mac, so this table is never synced.
struct ExportRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_export"
    var id: UUID
    var transcriptId: UUID
    var path: String
    var sha256: String
    var exportedAt: Date
}

/// The user's change to a paragraph: its text, who said it, or that it is left out. The
/// original stays as it was heard.
public struct ParagraphEdit: Sendable, Equatable {
    public var text: String?
    public var speaker: Speaker?
    public var deleted: Bool

    public init(text: String? = nil, speaker: Speaker? = nil, deleted: Bool = false) {
        self.text = text
        self.speaker = speaker
        self.deleted = deleted
    }

    var isEmpty: Bool { text == nil && speaker == nil && !deleted }
}

extension Speaker {
    /// How the store names a speaker: names and edits refer to it, so it never changes.
    var key: String {
        switch self {
        case .me: "me"
        case .unknown: "unknown"
        case .remote(let slot): "remote:\(slot)"
        }
    }

    init?(key: String) {
        switch key {
        case "me": self = .me
        case "unknown": self = .unknown
        default:
            guard key.hasPrefix("remote:"), let slot = Int(key.dropFirst("remote:".count)) else {
                return nil
            }
            self = .remote(slot: slot)
        }
    }
}

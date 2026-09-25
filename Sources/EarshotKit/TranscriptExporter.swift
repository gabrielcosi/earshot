import Foundation

/// Writes a transcript's Markdown copy into the transcripts folder. Earshot updates the file only
/// while it holds exactly what Earshot last wrote there: a file changed outside Earshot is never
/// written over, and one that was moved or deleted is not brought back. Either one is stale.
public struct TranscriptExporter: Sendable {
    public enum Status: Sendable, Equatable {
        /// Not written to this folder yet.
        case notExported
        case current(URL)
        /// Changed outside Earshot, so no longer updated.
        case edited(URL)
        /// Moved or deleted, so not written again.
        case missing(URL)
    }

    let store: TranscriptStore

    public init(store: TranscriptStore) {
        self.store = store
    }

    /// Brings the transcript's file in `folder` up to date with the store. The first export
    /// creates a new file and never replaces one already there, so two sessions in the same
    /// minute get two files.
    @discardableResult
    public func export(_ transcript: UUID, to folder: URL, rules: WordRules? = nil) throws
        -> Status
    {
        guard let view = try store.view(transcript) else { return .notExported }
        let contents = Data(view.markdown(rules: rules).utf8)
        switch try status(of: transcript, in: folder) {
        case .current(let file):
            if (try? Data(contentsOf: file)) != contents {
                try contents.write(to: file, options: .atomic)
                try store.recordExport(of: transcript, at: file, contents: contents)
            }
            return .current(file)
        case .notExported:
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = try writeNew(
                contents, in: folder, named: MarkdownExport.filename(for: view.startedAt))
            try store.recordExport(of: transcript, at: file, contents: contents)
            return .current(file)
        case let stale:
            return stale
        }
    }

    /// Writes a copy where the user chose in a save panel, which already asked before replacing
    /// a file. A copy in the transcripts folder becomes the file Earshot keeps up to date.
    public func saveCopy(_ transcript: UUID, to file: URL, folder: URL, rules: WordRules? = nil)
        throws
    {
        guard let view = try store.view(transcript) else { return }
        let contents = Data(view.markdown(rules: rules).utf8)
        try contents.write(to: file, options: .atomic)
        if Self.same(file.deletingLastPathComponent(), folder) {
            try store.recordExport(of: transcript, at: file, contents: contents)
        }
    }

    /// Whether the transcript's file in `folder` is still what Earshot last wrote. An export in
    /// another folder, from before the folder was changed, is left where it is and not counted.
    public func status(of transcript: UUID, in folder: URL) throws -> Status {
        guard let record = try store.exportRecord(of: transcript) else { return .notExported }
        let file = URL(filePath: record.path)
        guard Self.same(file.deletingLastPathComponent(), folder) else { return .notExported }
        guard FileManager.default.fileExists(atPath: record.path) else { return .missing(file) }
        guard let contents = try? Data(contentsOf: file),
            TranscriptStore.hash(contents) == record.sha256
        else { return .edited(file) }
        return .current(file)
    }

    /// Creates the file under the first free name: a file is only ever created, never replaced.
    private func writeNew(_ contents: Data, in folder: URL, named name: String) throws -> URL {
        var number = 1
        while true {
            let file = Self.file(named: name, number: number, in: folder)
            do {
                try contents.write(to: file, options: .withoutOverwriting)
                return file
            } catch CocoaError.fileWriteFileExists {
                number += 1
            }
        }
    }

    /// The first name in `folder` no file has yet, numbered as a first export would be, so a save
    /// panel never suggests a file that is already there.
    public static func freeFile(named name: String, in folder: URL) -> URL {
        var number = 1
        while true {
            let file = file(named: name, number: number, in: folder)
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                return file
            }
            number += 1
        }
    }

    /// "2026-09-25 1830 transcript.md", then "… transcript 2.md" and on.
    private static func file(named name: String, number: Int, in folder: URL) -> URL {
        guard number > 1 else { return folder.appending(path: name) }
        let base = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        return folder.appending(path: "\(base) \(number).\(suffix)")
    }

    private static func same(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            .trimmingSuffix("/")
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            .trimmingSuffix("/")
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}

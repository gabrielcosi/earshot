import EarshotKit
import Foundation
import Observation

/// The transcripts in the transcripts folder, with what the sidebar shows of each.
@Observable
final class SavedTranscripts {
    nonisolated struct Entry: Identifiable, Sendable {
        let file: URL
        /// The title the user gave it; nil while it has the one Earshot wrote.
        let title: String?
        let date: Date
        /// Where the last line starts: the session's length, give or take that line.
        let length: Double?
        var id: URL { file }
    }

    private(set) var entries: [Entry] = []
    @ObservationIgnored private var loading: Task<Void, Never>?

    func reload(_ folder: URL) {
        loading?.cancel()
        loading = Task {
            let read = await Self.read(folder)
            guard !Task.isCancelled else { return }
            entries = read
        }
    }

    /// When a session started: from its file name, which Earshot writes with the time in it, or
    /// when the file was made, for a file named some other way.
    nonisolated static func date(of file: URL) -> Date {
        MarkdownExport.date(fromFilename: file.lastPathComponent)
            ?? (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate)
            ?? .distantPast
    }

    /// The title the user gave the transcript, or nil while it has Earshot's own, which only
    /// repeats the date and time shown beside it. A file with no title, named some other way, goes
    /// by its name.
    nonisolated static func title(of file: URL, document: TranscriptDocument) -> String? {
        let name = file.lastPathComponent
        if document.title.isEmpty {
            return MarkdownExport.date(fromFilename: name) == nil
                ? file.deletingPathExtension().lastPathComponent : nil
        }
        return MarkdownExport.hasDefaultTitle(document.title, filename: name) ? nil : document.title
    }

    @concurrent
    nonisolated private static func read(_ folder: URL) async -> [Entry] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" } ?? []
        return files.compactMap { file in
            guard let markdown = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let document = TranscriptDocument(markdown: markdown)
            return Entry(
                file: file, title: title(of: file, document: document), date: date(of: file),
                length: TranscriptLength.of(document))
        }
    }
}

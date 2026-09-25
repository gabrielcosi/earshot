import EarshotCapture
import EarshotKit
import Foundation
import os

/// The store, where every transcript lives, and the Markdown copies written from it into the
/// transcripts folder.
extension SessionController {
    /// Inside the container, next to the models and preferences.
    private static let storeFolder = URL.applicationSupportDirectory.appending(path: "Earshot")
    static let audioFolder = storeFolder.appending(path: "Audio")

    /// A store that cannot be opened, on a full disk or a damaged file, leaves a session only its
    /// Markdown file: the problem says so from launch.
    static func openStore() -> (TranscriptStore, Problem?) {
        do {
            return (
                try TranscriptStore.open(at: storeFolder.appending(path: "Earshot.sqlite")), nil
            )
        } catch {
            Logger(subsystem: "com.gabrielcosi.earshot", category: "session")
                .error("opening the store failed: \(error, privacy: .public)")
            guard let memory = try? TranscriptStore.inMemory() else {
                fatalError("SQLite could not open an in-memory database: \(error)")
            }
            return (memory, .savingFailed(actionable(error)))
        }
    }

    /// Ends the session in the store, and writes its Markdown file.
    func seal() async {
        guard let savedID else { return }
        sealed = true
        do {
            try store.seal(savedID, at: .now)
        } catch {
            reportSavingFailed(error)
        }
        await export(savedID)
    }

    func reportSavingFailed(_ error: any Error) {
        log.error("saving failed: \(error, privacy: .public)")
        problems.report(.savingFailed(Self.actionable(error)))
    }

    /// Names a transcript's speakers in the store, and in the session still open in the app.
    func name(speakers names: [Speaker: String], in transcript: UUID) {
        do {
            try store.rename(transcript, names)
        } catch {
            reportSavingFailed(error)
            return
        }
        if transcript == savedID {
            for (speaker, name) in names {
                let name = name.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { self.names[speaker] = name }
            }
        }
        scheduleExport(transcript)
    }

    /// At launch, before a session can start: a session a crash or a forced quit left open is
    /// sealed as it was. Later, any open transcript is the session being recorded.
    func sealUnfinished() {
        do {
            let unfinished = try store.sealUnfinished()
            if !unfinished.isEmpty {
                log.notice("sealed \(unfinished.count) unfinished transcripts")
            }
        } catch {
            reportSavingFailed(error)
        }
    }

    /// Every sealed transcript without a Markdown file gets one.
    func exportUnexported() {
        do {
            for transcript in try store.unexported() { scheduleExport(transcript) }
        } catch {
            reportSavingFailed(error)
        }
    }

    /// Exports after naming, a summary, a late translation, or an edit. Changes that land while
    /// a transcript's export runs are written by one more export after it, not one each.
    func scheduleExport(_ transcript: UUID) {
        guard exportRuns[transcript] == nil else {
            exportAgain.insert(transcript)
            return
        }
        exportRuns[transcript] = Task {
            repeat {
                exportAgain.remove(transcript)
                await runExport(transcript)
            } while exportAgain.contains(transcript)
            exportRuns[transcript] = nil
        }
    }

    /// Returns once the transcript's file is written, for a session that ends as the app quits.
    func export(_ transcript: UUID) async {
        scheduleExport(transcript)
        await exportRuns[transcript]?.value
    }

    var exporting: Bool { !exportRuns.isEmpty }

    /// Returns once no Markdown file is being written, for the app to quit.
    func finishExports() async {
        while let run = exportRuns.values.first { await run.value }
    }

    private func runExport(_ transcript: UUID) async {
        let (exporter, folder, rules) = (
            TranscriptExporter(store: store), preferences.transcriptsFolder, rules
        )
        do {
            exports[transcript] = try await Self.export(
                transcript, with: exporter, to: folder, rules: rules)
            problems.resolve { if case .exportFailed = $0 { true } else { false } }
        } catch {
            log.error("export failed: \(error, privacy: .public)")
            problems.report(.exportFailed(Self.actionable(error)))
        }
    }

    @concurrent
    nonisolated private static func export(
        _ transcript: UUID, with exporter: TranscriptExporter, to folder: URL, rules: WordRules
    ) async throws -> TranscriptExporter.Status {
        try exporter.export(transcript, to: folder, rules: rules)
    }

    /// Reads the file again: it may have been changed or deleted since Earshot last looked.
    func checkExport(_ transcript: UUID) {
        exports[transcript] = try? TranscriptExporter(store: store).status(
            of: transcript, in: preferences.transcriptsFolder)
    }

    /// Export…: a copy where the user chose, which becomes the file kept up to date when it is
    /// in the transcripts folder.
    func saveCopy(_ transcript: UUID, to file: URL) {
        do {
            try TranscriptExporter(store: store).saveCopy(
                transcript, to: file, folder: preferences.transcriptsFolder, rules: rules)
        } catch {
            log.error("export failed: \(error, privacy: .public)")
            problems.report(.exportFailed(Self.actionable(error)))
        }
        checkExport(transcript)
    }

    /// Export Audio…: both sides mixed into one channel, so the file plays in both ears in any
    /// player. The save panel asked before replacing a file already there.
    func saveAudio(_ audio: URL, to file: URL) async {
        do {
            try await Self.exportMix(audio, to: file)
        } catch {
            log.error("exporting the audio failed: \(error, privacy: .public)")
            problems.report(.audioNotExported(Self.actionable(error)))
        }
    }

    /// Written in full to the volume's replacement folder first, then swapped in, so an export
    /// that fails part way leaves the file it would have replaced as it was.
    @concurrent
    nonisolated private static func exportMix(_ audio: URL, to file: URL) async throws {
        let manager = FileManager.default
        let folder = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: file, create: true)
        defer { try? manager.removeItem(at: folder) }
        let copy = folder.appending(path: file.lastPathComponent)
        try TranscriptAudio.exportMix(of: audio, to: copy)
        if manager.fileExists(atPath: file.path(percentEncoded: false)) {
            _ = try manager.replaceItemAt(file, withItemAt: copy)
        } else {
            try manager.moveItem(at: copy, to: file)
        }
    }
}

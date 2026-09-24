import EarshotKit
import Foundation
import Observation
import os

/// The downloadable speech models, where they live, and which ones are selected.
@Observable
final class ModelLibrary {
    let catalog: ModelCatalog
    let root = URL.applicationSupportDirectory.appending(path: "Earshot/Models")

    private(set) var installations: [String: SpeechModel.Installation] = [:]

    var installed: Set<String> { Set(installations.keys) }

    func isOutdated(_ repo: String) -> Bool {
        installations[repo]?.outdated == true
    }
    /// Download progress in 0...1 per repository, present only while downloading.
    private(set) var progress: [String: Double] = [:]
    var lastError: String?

    var transcription: String {
        didSet { UserDefaults.standard.set(transcription, forKey: "transcriptionModel") }
    }
    var diarization: String {
        didSet { UserDefaults.standard.set(diarization, forKey: "diarizationModel") }
    }

    private static let defaultTranscription = "nvidia/nemotron-3.5-asr-streaming-0.6b"
    private static let defaultDiarization = "nvidia/Nemotron-3-Diarization"

    @ObservationIgnored private var downloads: [String: Task<Void, Never>] = [:]
    private let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "models")

    init() {
        let index = Bundle.main.url(forResource: "model-index", withExtension: "json")
        catalog = index.flatMap { try? ModelCatalog(indexData: Data(contentsOf: $0)) } ?? .empty
        let defaults = UserDefaults.standard
        transcription = defaults.string(forKey: "transcriptionModel") ?? Self.defaultTranscription
        diarization = defaults.string(forKey: "diarizationModel") ?? Self.defaultDiarization
        refresh()
    }

    /// The files the engine should load, or nil when the selected recognizer is not downloaded.
    /// Diarization is optional: without its model the engine transcribes without speakers.
    var selection: EngineServer.Models? {
        guard let asr = installations[transcription]?.file else { return nil }
        return EngineServer.Models(
            transcription: asr, diarization: installations[diarization]?.file)
    }

    func download(_ model: SpeechModel) {
        guard downloads[model.repo] == nil else { return }
        progress[model.repo] = 0
        lastError = nil
        downloads[model.repo] = Task {
            do {
                try await ModelDownloader.download(
                    from: model.downloadURL, to: model.localURL(in: root), sha256: model.sha256
                ) { fraction in
                    Task { @MainActor in self.progress[model.repo] = fraction }
                }
                removeOtherRevisions(of: model)
            } catch is CancellationError {
            } catch {
                log.error(
                    "\(model.repo, privacy: .public) download failed: \(error, privacy: .public)")
                lastError = "\(model.repo): \(error.localizedDescription)"
            }
            progress[model.repo] = nil
            downloads[model.repo] = nil
            refresh()
        }
    }

    func cancel(_ model: SpeechModel) {
        downloads[model.repo]?.cancel()
    }

    func delete(_ model: SpeechModel) {
        try? FileManager.default.removeItem(at: root.appending(path: model.repo))
        refresh()
    }

    /// A new revision replaces the old one on disk once it is complete and verified.
    private func removeOtherRevisions(of model: SpeechModel) {
        let directory = root.appending(path: model.repo)
        let revisions =
            (try? FileManager.default.contentsOfDirectory(
                atPath: directory.path(percentEncoded: false))) ?? []
        for revision in revisions where revision != model.revision {
            try? FileManager.default.removeItem(at: directory.appending(path: revision))
        }
    }

    private func refresh() {
        installations = catalog.models.reduce(into: [:]) { result, model in
            result[model.repo] = model.installation(in: root)
        }
    }
}

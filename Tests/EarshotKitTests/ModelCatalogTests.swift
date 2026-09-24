import Foundation
import Testing

@testable import EarshotKit

@Suite struct ModelCatalogTests {
    private func catalog() throws -> ModelCatalog {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/model-index", withExtension: "json"))
        return try ModelCatalog(indexData: Data(contentsOf: url))
    }

    @Test func offersOnlyStreamingRecognizersAndDiarizers() throws {
        let catalog = try catalog()
        #expect(
            catalog.models(for: .transcription).map(\.repo) == [
                "nvidia/nemotron-3.5-asr-streaming-0.6b",
                "nvidia/nemotron-speech-streaming-en-0.6b",
            ])
        #expect(
            catalog.models(for: .diarization).map(\.repo) == [
                "nvidia/Nemotron-3-Diarization",
                "nvidia/diar_streaming_sortformer_4spk-v2",
            ])
    }

    @Test func storesFilesInTheEngineCacheLayout() throws {
        let model = try #require(try catalog().model(repo: "nvidia/Nemotron-3-Diarization"))
        let root = URL(filePath: "/models")
        #expect(
            model.localURL(in: root).path(percentEncoded: false)
                == "/models/nvidia/Nemotron-3-Diarization/\(model.revision)/\(model.filename)")
        #expect(
            model.downloadURL.absoluteString
                == "https://huggingface.co/nvidia/Nemotron-3-Diarization/resolve/\(model.revision)/\(model.filename)"
        )
    }

    @Test func aPartialFileIsNotInstalled() throws {
        let model = try #require(try catalog().model(repo: "nvidia/Nemotron-3-Diarization"))
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Application Support \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = model.localURL(in: root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 10).write(to: file)
        #expect(!model.isInstalled(in: root))
    }
}

@Suite struct ModelInstallTests {
    @Test func aCompleteFileUnderAPathWithSpacesIsInstalled() throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/model-index", withExtension: "json"))
        let catalog = try ModelCatalog(indexData: Data(contentsOf: url))
        let model = try #require(catalog.model(repo: "nvidia/Nemotron-3-Diarization"))
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Application Support \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = model.localURL(in: root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(model.size))
        try handle.close()
        #expect(model.isInstalled(in: root))
    }
}

@Suite struct ModelOverrideTests {
    @Test func nemotron35UsesTheReconversionWithAnEmbeddedTokenizer() throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/model-index", withExtension: "json"))
        let catalog = try ModelCatalog(indexData: Data(contentsOf: url))
        let model = try #require(catalog.model(repo: "nvidia/nemotron-3.5-asr-streaming-0.6b"))
        #expect(model.revision == "ea30d66debe3740a08b573244286791d423d6b3e")
        #expect(model.size == 742_090_464)
        #expect(model.sha256 == "3fc991d3badad7277c11030a7519832cddaf2057aafed6d4b25147e953a070b1")
    }

    @Test func theIndexWinsOnceItPinsAnotherRevision() throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/model-index", withExtension: "json"))
        let index = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(
                of: "1c8deaecc64b91f034d73e08dd8b64625eb3395d",
                with: "0000000000000000000000000000000000000000")
        let catalog = try ModelCatalog(indexData: Data(index.utf8))
        let model = try #require(catalog.model(repo: "nvidia/nemotron-3.5-asr-streaming-0.6b"))
        #expect(model.revision == "0000000000000000000000000000000000000000")
    }
}

private let engineIndex = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "../../vendor/NeMo-Speech.cpp/models/index.json").standardized

/// Fails after an engine update whose index no longer pins what an override replaces. The app
/// already follows the index then; the override, and the revision `mise run engine:models`
/// pins, are left to remove.
@Suite(.enabled(if: FileManager.default.fileExists(atPath: engineIndex.path())))
struct EngineIndexTests {

    @Test func overridesStillReplaceWhatTheEnginePins() throws {
        // The same decoding the app does, without the overrides.
        let catalog = try ModelCatalog(indexData: Data(contentsOf: engineIndex), overrides: [:])
        for (repo, override) in ModelCatalog.overrides {
            let pinned = try #require(catalog.model(repo: repo)).revision
            #expect(
                pinned == override.replaces,
                "The engine now pins \(repo) at \(pinned). Remove its override in ModelCatalog and the revision in the engine:models task."
            )
        }
    }
}

@Suite struct ModelRevisionTests {
    private func model() throws -> SpeechModel {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/model-index", withExtension: "json"))
        return try #require(
            try ModelCatalog(indexData: Data(contentsOf: url)).model(
                repo: "nvidia/nemotron-3.5-asr-streaming-0.6b"))
    }

    private func install(_ model: SpeechModel, revision: String, in root: URL) throws {
        let file = root.appending(path: model.repo).appending(path: revision)
            .appending(path: model.filename)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: file.path(percentEncoded: false), contents: Data("x".utf8))
    }

    @Test func anOlderRevisionIsUsableButOutdated() throws {
        let model = try model()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try install(model, revision: "1c8deaecc64b91f034d73e08dd8b64625eb3395d", in: root)
        let installed = try #require(model.installation(in: root))
        #expect(installed.outdated)
        #expect(installed.file.path(percentEncoded: false).contains("1c8deaec"))
    }

    @Test func nothingDownloadedIsNoInstallation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(try model().installation(in: root) == nil)
    }
}

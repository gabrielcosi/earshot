import Foundation

/// The speech models the app can download, read from the engine's own `models/index.json` so
/// revisions, sizes, and checksums follow the engine version.
public struct ModelCatalog: Sendable {
    public enum Kind: Sendable {
        case transcription
        case diarization
    }

    /// Only models the realtime WebSocket can stream with, in the order the library lists them.
    /// Parakeet TDT and CTC are offline or buffered heads, so they are left out.
    private static let offered: [(repo: String, kind: Kind)] = [
        ("nvidia/nemotron-3.5-asr-streaming-0.6b", .transcription),
        ("nvidia/nemotron-speech-streaming-en-0.6b", .transcription),
        ("nvidia/Nemotron-3-Diarization", .diarization),
        ("nvidia/diar_streaming_sortformer_4spk-v2", .diarization),
    ]

    /// Files newer than the engine's index pins. NVIDIA re-converted Nemotron 3.5 on 2026-09-10
    /// ("Re-convert GGUF with embedded SentencePiece tokenizer"); the August file the index pins
    /// lacks `asr.tokenizer.spm_model`, so the engine disables word boosting with it.
    struct Override {
        /// The revision the index pinned when the override was written. Once the index pins
        /// anything else, the index wins: it has caught up, or moved past this file.
        let replaces: String
        let revision: String
        let size: Int64
        let sha256: String
    }

    static let overrides = [
        "nvidia/nemotron-3.5-asr-streaming-0.6b": Override(
            replaces: "1c8deaecc64b91f034d73e08dd8b64625eb3395d",
            revision: "ea30d66debe3740a08b573244286791d423d6b3e", size: 742_090_464,
            sha256: "3fc991d3badad7277c11030a7519832cddaf2057aafed6d4b25147e953a070b1")
    ]

    public let models: [SpeechModel]

    /// A catalog with nothing to offer, for a bundle without the engine's index.
    public static let empty = ModelCatalog(models: [])

    private init(models: [SpeechModel]) {
        self.models = models
    }

    public init(indexData: Data) throws {
        try self.init(indexData: indexData, overrides: Self.overrides)
    }

    init(indexData: Data, overrides: [String: Override]) throws {
        let index = try JSONDecoder().decode(Index.self, from: indexData)
        models = Self.offered.compactMap { offer in
            guard let entry = index.models.first(where: { $0.repo == offer.repo }),
                let artifact = entry.artifacts.first(where: {
                    $0.role == (offer.kind == .transcription ? "asr" : "diarization")
                })
            else { return nil }
            let pinned = artifact.revision ?? entry.revision
            let override = overrides[entry.repo].flatMap { $0.replaces == pinned ? $0 : nil }
            return SpeechModel(
                repo: entry.repo,
                kind: offer.kind,
                revision: override?.revision ?? pinned,
                filename: artifact.filename,
                size: override?.size ?? artifact.size,
                sha256: override?.sha256 ?? artifact.sha256,
                license: entry.license)
        }
    }

    public func models(for kind: Kind) -> [SpeechModel] {
        models.filter { $0.kind == kind }
    }

    public func model(repo: String) -> SpeechModel? {
        models.first { $0.repo == repo }
    }

    private struct Index: Decodable {
        let models: [Entry]
    }

    private struct Entry: Decodable {
        let repo: String
        let revision: String
        let license: String?
        let artifacts: [Artifact]
    }

    private struct Artifact: Decodable {
        let role: String
        let filename: String
        let size: Int64
        let sha256: String
        let revision: String?
    }
}

public struct SpeechModel: Identifiable, Sendable, Equatable {
    public let repo: String
    public let kind: ModelCatalog.Kind
    public let revision: String
    public let filename: String
    public let size: Int64
    public let sha256: String
    public let license: String?

    public var id: String { repo }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(filename)")
            ?? URL(filePath: "/")
    }

    /// The engine's cache layout, so `nemo-speech` resolves the same files by repository name.
    public func localURL(in root: URL) -> URL {
        root.appending(path: repo).appending(path: revision).appending(path: filename)
    }

    public struct Installation: Equatable, Sendable {
        public let file: URL
        /// An earlier revision: it works, and the library offers the current one as an update.
        public let outdated: Bool
    }

    /// The current revision when complete, otherwise any earlier revision already on disk, so a
    /// revision bump never leaves the user without a working model.
    public func installation(in root: URL) -> Installation? {
        if isInstalled(in: root) { return Installation(file: localURL(in: root), outdated: false) }
        let directory = root.appending(path: repo)
        let revisions =
            (try? FileManager.default.contentsOfDirectory(
                atPath: directory.path(percentEncoded: false))) ?? []
        for revision in revisions.sorted() where revision != self.revision {
            let file = directory.appending(path: revision).appending(path: filename)
            if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                return Installation(file: file, outdated: true)
            }
        }
        return nil
    }

    /// Present at its full size. The checksum is verified once, when the download completes.
    public func isInstalled(in root: URL) -> Bool {
        let path = localURL(in: root).path(percentEncoded: false)
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber
        return size?.int64Value == self.size
    }
}

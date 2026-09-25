import EarshotKit
import Foundation
import os

/// Keeps the bundled `nemo-speech serve` running with the models chosen in the library.
final class EngineServer {
    struct Models: Equatable {
        let transcription: URL
        let diarization: URL?
    }

    /// The running engine's address, with a bearer key made fresh for each launch; nil while
    /// none runs. Browsers let any web page reach localhost; without the key, a page could run
    /// the engine on this Mac's GPU or crowd out a recording's sessions.
    private(set) var endpoint: EngineEndpoint?
    private var process: Process?
    private var running: Models?
    /// A start in progress. Warming up from the menu and pressing Start can overlap; the second
    /// caller waits for the first instead of launching a second engine.
    private var starting: (models: Models, task: Task<EngineEndpoint, any Error>)?

    var isRunning: Bool { process?.isRunning == true }
    private let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "engine")

    /// A cold start loads ~810 MB of GGUFs and takes about 6 s on a recent Apple silicon Mac;
    /// 5x covers a cold page cache.
    private static let startupTimeout = Duration.seconds(30)

    /// Returns the engine running `models`, starting it, or restarting it when it runs others.
    func ensureRunning(with models: Models) async throws -> EngineEndpoint {
        if let starting, starting.models == models { return try await starting.task.value }
        let task = Task { try await start(models) }
        starting = (models, task)
        defer { starting = nil }
        return try await task.value
    }

    /// Only an engine this app started is ever used: it listens on a port the system picked,
    /// with this launch's key, and stops when the app stops, however the app stops (ADR-0001).
    private func start(_ models: Models) async throws -> EngineEndpoint {
        if isRunning, running == models, let endpoint { return endpoint }
        stop()
        let binary = Bundle.main.bundleURL.appending(
            path: "Contents/Helpers/nemo-speech/bin/nemo-speech")
        guard FileManager.default.isExecutableFile(atPath: binary.path(percentEncoded: false)),
            let config = Bundle.main.url(forResource: "server", withExtension: "yaml")
        else { throw EngineError.missingBinary }

        let key = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }
            .joined()
        let logURL = URL.libraryDirectory.appending(path: "Logs/Earshot-engine.log")
        FileManager.default.createFile(atPath: logURL.path(percentEncoded: false), contents: nil)
        let launched = try await EngineLaunch.start(
            binary: binary,
            arguments: EngineLaunch.arguments(
                config: config, transcription: models.transcription,
                diarization: models.diarization),
            // The environment, not an argument: arguments show up in every process listing.
            environment: ProcessInfo.processInfo.environment.merging(
                ["NEMO_SPEECH_HTTP_API_KEY": key]) { _, key in key },
            log: try FileHandle(forWritingTo: logURL), timeout: Self.startupTimeout)
        log.info(
            "launched engine pid \(launched.process.processIdentifier) at \(launched.address, privacy: .public)"
        )
        let endpoint = EngineEndpoint(url: launched.address, apiKey: key)
        (process, running, self.endpoint) = (launched.process, models, endpoint)
        return endpoint
    }

    func stop() {
        process?.terminate()
        process?.waitUntilExit()
        (process, running, endpoint) = (nil, nil, nil)
    }
}

enum EngineError: LocalizedError {
    case missingBinary
    case missingModel

    var errorDescription: String? {
        switch self {
        case .missingBinary: "The speech engine is missing from the app bundle."
        case .missingModel: "Download a transcription model in Settings first."
        }
    }
}

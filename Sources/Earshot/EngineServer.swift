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
    private var engine: EngineLaunch.Running?
    /// Which launch `engine` is; an exit reported for any other was already stopped or replaced.
    private var launch: UUID?
    /// Called when the running engine exits without being stopped.
    var onExit: (() -> Void)?
    private var running: Models?
    /// A start in progress. Warming up from the menu and pressing Start can overlap; the second
    /// caller waits for the first instead of launching a second engine.
    private var starting: (models: Models, task: Task<EngineEndpoint, any Error>)?

    var isRunning: Bool { engine?.process.isRunning == true }
    private let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "engine")

    /// A cold start loads ~810 MB of GGUFs and takes about 6 s on a recent Apple silicon Mac;
    /// 5x covers a cold page cache.
    private static let startupTimeout = Duration.seconds(30)
    /// With no connection open the engine exits 60-590 ms after SIGTERM (13 runs on Apple
    /// silicon, both models loaded); past a second it is held by a connection and gets killed.
    /// The main thread waits this long at most, at quit or unload.
    private static let stopGrace = Duration.seconds(1)

    static let logURL = URL.libraryDirectory.appending(path: "Logs/Earshot-engine.log")

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
        let launch = UUID()
        let launched = try await EngineLaunch.start(
            binary: binary,
            arguments: EngineLaunch.arguments(
                config: config, transcription: models.transcription,
                diarization: models.diarization),
            // The environment, not an argument: arguments show up in every process listing.
            environment: ProcessInfo.processInfo.environment.merging(
                ["NEMO_SPEECH_HTTP_API_KEY": key]) { _, key in key },
            log: try EngineLog.open(Self.logURL), timeout: Self.startupTimeout
        ) { [weak self] in
            Task { @MainActor in self?.exited(launch) }
        }
        log.info(
            "launched engine pid \(launched.process.processIdentifier) at \(launched.address, privacy: .public)"
        )
        let endpoint = EngineEndpoint(url: launched.address, apiKey: key)
        (engine, running, self.endpoint, self.launch) = (launched, models, endpoint, launch)
        // An exit reported before the line above was ignored as another launch's.
        guard launched.process.isRunning else {
            stop()
            throw EngineLaunch.Failure.exited
        }
        return endpoint
    }

    func stop() {
        engine?.stop(grace: Self.stopGrace)
        (engine, running, endpoint, launch) = (nil, nil, nil, nil)
    }

    private func exited(_ launch: UUID) {
        guard launch == self.launch else { return }
        log.error("engine pid \(self.engine?.process.processIdentifier ?? 0) exited")
        (engine, running, endpoint, self.launch) = (nil, nil, nil, nil)
        onExit?()
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

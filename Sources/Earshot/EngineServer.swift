import EarshotKit
import Foundation
import os

/// Keeps the bundled `nemo-speech serve` running with the models chosen in the library.
final class EngineServer {
    struct Models: Equatable {
        let transcription: URL
        let diarization: URL?
    }

    /// The engine's address plus a bearer key made fresh for each launch of the app. Browsers
    /// let any web page open a WebSocket to localhost; without the key, a page could run the
    /// engine on this Mac's GPU or crowd out a recording's sessions.
    let endpoint: EngineEndpoint
    private var process: Process?
    private var running: Models?
    /// A start in progress. Warming up from the menu and pressing Start can overlap; the second
    /// caller waits for the first instead of launching a second engine onto the same port.
    private var starting: (models: Models, task: Task<Void, any Error>)?

    var isRunning: Bool { process?.isRunning == true }
    private let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "engine")

    /// A cold start loads ~810 MB of GGUFs and takes about 6 s on a recent Apple silicon Mac; 5x covers a
    /// cold page cache.
    private static let startupTimeout = Duration.seconds(30)

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let url = URL(string: info["EarshotServerURL"] as? String ?? "") ?? URL(filePath: "/")
        let key = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }
        endpoint = EngineEndpoint(url: url, apiKey: key.joined())
    }

    /// Returns once `/ready` answers with `models` loaded, restarting the engine when it runs
    /// others. An engine this app did not launch (`mise run serve`) is used as it is.
    func ensureRunning(with models: Models) async throws {
        if let starting, starting.models == models { return try await starting.task.value }
        let task = Task { try await start(models) }
        starting = (models, task)
        defer { starting = nil }
        try await task.value
    }

    private func start(_ models: Models) async throws {
        if process?.isRunning == true, running != models { stop() }
        if process?.isRunning != true {
            if await isReady() {
                log.notice("using an engine this app did not launch")
                return
            }
            try launch(models)
        }
        let deadline = ContinuousClock.now + Self.startupTimeout
        while ContinuousClock.now < deadline {
            if await isReady() { return }
            if process?.isRunning == false { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw EngineError.notReady(endpoint.url)
    }

    func stop() {
        process?.terminate()
        process?.waitUntilExit()
        process = nil
        running = nil
    }

    private func isReady() async -> Bool {
        var request = URLRequest(url: endpoint.url.appending(path: "ready"))
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func launch(_ models: Models) throws {
        let binary = Bundle.main.bundleURL.appending(
            path: "Contents/Helpers/nemo-speech/bin/nemo-speech")
        guard FileManager.default.isExecutableFile(atPath: binary.path(percentEncoded: false)),
            let config = Bundle.main.url(forResource: "server", withExtension: "yaml")
        else { throw EngineError.missingBinary }

        let process = Process()
        process.executableURL = binary
        process.arguments =
            [
                "serve", "--config", config.path(percentEncoded: false), "--asr-model",
                models.transcription.path(percentEncoded: false),
            ]
            + (models.diarization.map { ["--diar-model", $0.path(percentEncoded: false)] } ?? [])
            + ["--no-ui"]
        // The environment, not an argument: arguments show up in every process listing.
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["NEMO_SPEECH_HTTP_API_KEY": endpoint.apiKey ?? ""]) { _, key in key }
        let logURL = URL.libraryDirectory.appending(path: "Logs/Earshot-engine.log")
        FileManager.default.createFile(atPath: logURL.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        log.info("launched engine pid \(process.processIdentifier)")
        self.process = process
        running = models
    }
}

enum EngineError: LocalizedError {
    case missingBinary
    case notReady(URL)
    case missingModel

    var errorDescription: String? {
        switch self {
        case .missingBinary: "The speech engine is missing from the app bundle."
        case .notReady(let url): "The speech engine at \(url.absoluteString) did not become ready."
        case .missingModel: "Download a transcription model in Settings first."
        }
    }
}

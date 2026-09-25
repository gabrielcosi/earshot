import Foundation
import Testing

@testable import EarshotKit

@Suite struct EngineLaunchTests {
    @Test func theReadyEventGivesTheAddressTheEngineChose() {
        let line =
            #"{"capabilities":["asr","diarization"],"event":"listener.ready","transport":"http","url":"http://127.0.0.1:53611/"}"#
        #expect(EngineLaunch.address(fromEvent: line)?.absoluteString == "http://127.0.0.1:53611/")
    }

    @Test func otherOutputIsNoAddress() {
        #expect(
            EngineLaunch.address(fromEvent: "HTTP API listening on http://127.0.0.1:8765") == nil)
        #expect(EngineLaunch.address(fromEvent: #"{"event":"model.loaded"}"#) == nil)
        #expect(EngineLaunch.address(fromEvent: "") == nil)
    }

    /// The engine picks a free port and stops when the app does, so no launch can meet an
    /// engine another launch left behind.
    @Test func theEngineIsAskedForAFreePortAndToExitWithTheApp() {
        let arguments = EngineLaunch.arguments(
            config: URL(filePath: "/c.yaml"), transcription: URL(filePath: "/asr.gguf"),
            diarization: URL(filePath: "/diar.gguf"))
        #expect(arguments.starts(with: ["--json", "serve"]))
        #expect(arguments.contains("--exit-with-parent"))
        #expect(arguments.firstIndex(of: "--port").map { arguments[$0 + 1] } == "0")
        #expect(arguments.firstIndex(of: "--diar-model").map { arguments[$0 + 1] } == "/diar.gguf")
    }

    private static let ready = #"echo '{"event":"listener.ready","url":"http://127.0.0.1:1/"}'"#

    /// A stand-in engine: a shell running `script`.
    private func launch(_ script: String, onExit: @escaping @Sendable () -> Void = {})
        async throws -> EngineLaunch.Running
    {
        try await EngineLaunch.start(
            binary: URL(filePath: "/bin/sh"), arguments: ["-c", script], environment: [:],
            log: FileHandle.nullDevice, timeout: .seconds(10), onExit: onExit)
    }

    /// An engine that dies mid-session has to be noticed, or the session looks alive with
    /// nothing behind it.
    @Test(.timeLimit(.minutes(1))) func anEngineThatStopsAfterStartingIsReported() async throws {
        let (exits, exited) = AsyncStream<Void>.makeStream()
        let running = try await launch("\(Self.ready); exec sleep 60") { exited.yield() }
        #expect(running.address.port == 1)
        running.process.terminate()
        for await _ in exits { break }
        #expect(!running.process.isRunning)
    }

    @Test func anEngineThatStopsBeforeItIsReadyFailsTheStart() async {
        await #expect(throws: EngineLaunch.Failure.self) { try await launch("exit 3") }
    }

    /// The exit handler reports an exit only when this says the engine got ready first, so an
    /// engine that never started is not also reported as stopped.
    @Test func theFirstOutcomeStands() throws {
        let address = try #require(URL(string: "http://127.0.0.1:1/"))
        let exited = ReadySignal()
        exited.resolve(nil)
        #expect(exited.resolve(address) == .exited)
        let ready = ReadySignal()
        ready.resolve(address)
        #expect(ready.resolve(nil) == .ready(address))
    }
}

/// Two apps (two users, or two copies) each start their own engine: each gets its own port, and
/// neither engine accepts the other's key.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EARSHOT_LIVE"] == "1"))
struct LiveEngineLaunchTests {
    private let environment = ProcessInfo.processInfo.environment

    private func launch(key: String) async throws -> EngineLaunch.Running {
        let deps = try #require(environment["EARSHOT_DEPS"])
        let model = try #require(environment["EARSHOT_ASR_MODEL"])
        let config = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../config/server.yaml").standardized
        FileManager.default.createFile(atPath: "/tmp/earshot-launch-\(key).log", contents: nil)
        let log = try FileHandle(forWritingTo: URL(filePath: "/tmp/earshot-launch-\(key).log"))
        return try await EngineLaunch.start(
            binary: URL(filePath: deps).appending(path: "engine/bin/nemo-speech"),
            arguments: EngineLaunch.arguments(
                config: config, transcription: URL(filePath: model), diarization: nil),
            environment: environment.merging(["NEMO_SPEECH_HTTP_API_KEY": key]) { _, key in key },
            log: log, timeout: .seconds(30))
    }

    private func status(_ address: URL, key: String) async throws -> Int? {
        var request = URLRequest(url: address.appending(path: "v1/models"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode
    }

    @Test func eachLaunchHasItsOwnPortAndKey() async throws {
        async let first = launch(key: "first")
        async let second = launch(key: "second")
        let engines = try await [first, second]
        defer { engines.forEach { $0.process.terminate() } }
        #expect(engines[0].address.port != engines[1].address.port)
        #expect(try await status(engines[0].address, key: "first") == 200)
        #expect(try await status(engines[0].address, key: "second") == 401)
        #expect(try await status(engines[1].address, key: "second") == 200)
    }
}

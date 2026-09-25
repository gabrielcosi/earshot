import Foundation
import os

/// Starts `nemo-speech serve` for this app alone: on a port the system picks, and set to stop
/// when the app stops, however it stops. No launch can meet an engine another one left behind.
public enum EngineLaunch {
    public enum Failure: LocalizedError {
        case exited
        case notReady(Duration)

        public var errorDescription: String? {
            switch self {
            case .exited: "The speech engine stopped while it was starting."
            case .notReady(let timeout): "The speech engine did not start within \(timeout)."
            }
        }
    }

    public struct Running: @unchecked Sendable {
        public let process: Process
        /// Where the engine listens, as it reported after binding.
        public let address: URL
    }

    public static func arguments(config: URL, transcription: URL, diarization: URL?) -> [String] {
        ["--json", "serve", "--config", config.path(percentEncoded: false)]
            + ["--asr-model", transcription.path(percentEncoded: false)]
            + (diarization.map { ["--diar-model", $0.path(percentEncoded: false)] } ?? [])
            + ["--port", "0", "--exit-with-parent", "--no-ui"]
    }

    /// The address in the engine's `listener.ready` event, which it prints once its models are
    /// loaded and its port is bound.
    static func address(fromEvent line: String) -> URL? {
        struct Event: Decodable {
            let event: String
            let url: String?
        }
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)),
            event.event == "listener.ready", let url = event.url
        else { return nil }
        return URL(string: url)
    }

    /// Returns once the engine listens. Everything it prints goes to `log`; its output is read
    /// for as long as it runs, so it never blocks on a full pipe.
    public static func start(
        binary: URL, arguments: [String], environment: [String: String], log: FileHandle,
        timeout: Duration
    ) async throws -> Running {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = log
        let ready = ReadySignal()
        let lines = OSAllocatedUnfairLock(initialState: Data())
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                ready.resolve(nil)
                return
            }
            log.write(data)
            let complete = lines.withLock { pending -> [String] in
                pending.append(data)
                guard let last = pending.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
                let text = String(bytes: pending[..<last], encoding: .utf8) ?? ""
                pending.removeSubrange(...last)
                return text.split(separator: "\n").map(String.init)
            }
            if let address = complete.lazy.compactMap(address(fromEvent:)).first {
                ready.resolve(address)
            }
        }
        try process.run()
        let timer = Task {
            try await Task.sleep(for: timeout)
            ready.resolve(nil, timedOut: true)
        }
        defer { timer.cancel() }
        switch await ready.value() {
        case .ready(let address):
            return Running(process: process, address: address)
        case .exited:
            throw Failure.exited
        case .timedOut:
            process.terminate()
            throw Failure.notReady(timeout)
        }
    }
}

/// The first of: the engine's address, its output closing, or the timeout.
private final class ReadySignal: Sendable {
    enum Outcome: Sendable {
        case ready(URL)
        case exited
        case timedOut
    }

    private let state = OSAllocatedUnfairLock<(Outcome?, CheckedContinuation<Outcome, Never>?)>(
        initialState: (nil, nil))

    func resolve(_ address: URL?, timedOut: Bool = false) {
        let outcome: Outcome = address.map { .ready($0) } ?? (timedOut ? .timedOut : .exited)
        let waiting = state.withLock { state -> CheckedContinuation<Outcome, Never>? in
            guard state.0 == nil else { return nil }
            state.0 = outcome
            defer { state.1 = nil }
            return state.1
        }
        waiting?.resume(returning: outcome)
    }

    func value() async -> Outcome {
        await withCheckedContinuation { continuation in
            let settled = state.withLock { state -> Outcome? in
                if let outcome = state.0 { return outcome }
                state.1 = continuation
                return nil
            }
            if let settled { continuation.resume(returning: settled) }
        }
    }
}

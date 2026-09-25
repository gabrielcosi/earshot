import Foundation
import os

/// One transcription stream on the engine's `/v1/audio/transcriptions/realtime` WebSocket.
public final class RealtimeClient: Sendable {
    public let events: AsyncStream<ServerEvent>

    private let task: URLSessionWebSocketTask
    private let continuation: AsyncStream<ServerEvent>.Continuation
    private let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "realtime")
    private let chunker = OSAllocatedUnfairLock(initialState: PCMChunker())
    /// A final arrives within ~1.5 s of its speech, but one final can hold a long stretch of
    /// speech without an 0.8 s pause; a minute covers both with room to spare.
    private let history = OSAllocatedUnfairLock(initialState: AudioHistory(seconds: 60))

    public init(engine: EngineEndpoint, settings: SessionSettings) {
        task = URLSession.shared.webSocketTask(
            with: engine.request(
                "v1/audio/transcriptions/realtime",
                scheme: engine.url.scheme == "https" ? "wss" : "ws"))
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        task.resume()
        receive()
        send(.sessionUpdate(settings))
    }

    /// Little-endian PCM16 at the session's sample rate, in buffers of any size.
    public func send(audio: Data) {
        history.withLock { $0.append(audio) }
        for chunk in chunker.withLock({ $0.append(audio) }) { transmit(chunk) }
    }

    /// Asks the engine to flush the last utterance. It answers with that final and then
    /// `input_audio_buffer.committed`, after which the stream can be closed.
    public func commit() {
        if let rest = chunker.withLock({ $0.flush() }) { transmit(rest) }
        send(.commit)
    }

    /// The session's audio between two stream times, if still held.
    public func audio(from start: Double, to end: Double) -> Data? {
        history.withLock { $0.pcm(from: start, to: end) }
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
        continuation.finish()
    }

    private func transmit(_ audio: Data) {
        task.send(.data(audio)) { [log] error in
            if let error { log.error("audio send failed: \(error, privacy: .public)") }
        }
    }

    private func send(_ event: ClientEvent) {
        guard let text = try? event.encoded() else { return }
        task.send(.string(text)) { [log] error in
            if let error { log.error("event send failed: \(error, privacy: .public)") }
        }
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                do {
                    continuation.yield(try ServerEvent.decode(text))
                } catch {
                    log.error("undecodable event: \(text, privacy: .public)")
                }
                receive()
            case .success:
                receive()
            case .failure(let error):
                let reason = task.closeReason.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
                log.error(
                    "receive failed, close code \(self.task.closeCode.rawValue) \(reason, privacy: .public): \(error, privacy: .public)"
                )
                continuation.yield(.disconnected(error.localizedDescription))
                continuation.finish()
            }
        }
    }
}

import Foundation
import os

/// Something that takes a stream of PCM16 audio.
public protocol AudioReceiver: Sendable {
    func send(audio: Data)
}

extension RealtimeClient: AudioReceiver {}

/// Where a capture's audio goes. Until the engine has loaded, audio waits here; once a session is
/// attached, the waiting audio goes first and everything after it streams straight through, so a
/// session can start before the engine is ready without losing its opening words.
public final class AudioSink: Sendable {
    private struct State {
        var client: (any AudioReceiver)?
        var pending: [Data] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func send(_ pcm: Data) {
        state.withLock { state in
            if let client = state.client {
                client.send(audio: pcm)
            } else {
                state.pending.append(pcm)
            }
        }
    }

    /// Sending under the lock keeps the order: nothing captured meanwhile can overtake the
    /// waiting audio. `RealtimeClient.send` only queues, so the lock is held briefly.
    public func attach(_ client: any AudioReceiver) {
        state.withLock { state in
            for pcm in state.pending { client.send(audio: pcm) }
            state.pending = []
            state.client = client
        }
    }
}

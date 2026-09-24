import CEchoCanceller
import EarshotKit
import Foundation
import os

/// Removes what the speakers play from what the microphone hears, with WebRTC's AEC3: the
/// process tap is the far end and the microphone the near end. One lock serializes both, because
/// the tap and the microphone deliver on different threads.
///
/// Measured on a room's speakers with the tap as reference: remote speech bleeding in at
/// -28 dBFS came out at -55 to -58 dBFS, below the room's noise, and the engine transcribed
/// nothing from it. The tap leads the microphone by 90 to 100 ms, and AEC3 finds an echo up to
/// about 500 ms behind its reference, never ahead, so the far end must be fed as it arrives.
public final class EchoCanceller: Sendable {
    /// AEC3 works in 10 ms blocks: 160 samples of 16 kHz PCM16.
    static let blockBytes = Int(EARSHOT_AEC_BLOCK_SAMPLES) * 2

    private struct State {
        let handle: OpaquePointer
        var farEnd = PCMChunker(chunkBytes: blockBytes)
        var nearEnd = PCMChunker(chunkBytes: blockBytes)
    }

    private let state: OSAllocatedUnfairLock<State>

    public init?() {
        guard let handle = earshot_aec_create() else { return nil }
        state = OSAllocatedUnfairLock(uncheckedState: State(handle: handle))
    }

    deinit {
        earshot_aec_destroy(state.withLockUnchecked(\.handle))
    }

    /// What the speakers are playing, as it arrives.
    public func feedFarEnd(_ pcm: Data) {
        state.withLockUnchecked { state in
            for block in state.farEnd.append(pcm) {
                block.withUnsafeBytes {
                    earshot_aec_far_end(state.handle, $0.bindMemory(to: Int16.self).baseAddress)
                }
            }
        }
    }

    /// Microphone audio with the far end's echo removed. Whole blocks come back at once and a
    /// partial block waits for the next call, so the output trails the input by under 10 ms.
    public func process(_ pcm: Data) -> Data {
        state.withLockUnchecked { state in
            var cleaned = Data(capacity: pcm.count)
            for var block in state.nearEnd.append(pcm) {
                block.withUnsafeMutableBytes {
                    earshot_aec_near_end(state.handle, $0.bindMemory(to: Int16.self).baseAddress)
                }
                cleaned.append(block)
            }
            return cleaned
        }
    }

    /// Forgets the echo path and any partial blocks, for when the output device changes.
    public func reset() {
        state.withLockUnchecked { state in
            earshot_aec_reset(state.handle)
            state.farEnd = PCMChunker(chunkBytes: Self.blockBytes)
            state.nearEnd = PCMChunker(chunkBytes: Self.blockBytes)
        }
    }
}

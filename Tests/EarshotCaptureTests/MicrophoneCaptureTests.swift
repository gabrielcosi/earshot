@preconcurrency import AVFoundation
import Foundation
import Testing
import os

@testable import EarshotCapture

@Suite struct MicrophoneCaptureTests {
    /// Another process starting or stopping voice processing stops the engine and can change the
    /// input's format. The tap built for the new format must feed the same callback, so the
    /// microphone stream carries on at 16 kHz without the caller noticing.
    @Test func rebuiltTapFeedsTheSameCallbackAtTheNewRate() throws {
        let received = OSAllocatedUnfairLock(initialState: Data())
        let onAudio: @Sendable (Data) -> Void = { pcm in received.withLock { $0.append(pcm) } }

        // AVAudioEngine's input tap at 48 kHz stereo, then the hardware switching to 44.1 kHz mono.
        for (rate, channels) in [(48_000.0, AVAudioChannelCount(2)), (44_100.0, 1)] {
            let (format, buffers) = try Tone.second(
                rate: rate, channels: channels, interleaved: false, frames: 4096)
            let tap = try #require(MicrophoneTap(format: format, onAudio: onAudio))
            #expect(tap.format == format)
            buffers.forEach(tap.receive)
        }

        let output = Tone.samples(received.withLock { $0 })
        // Two seconds at 16 kHz; the converter holds back a filter's worth per format (1%).
        #expect(abs(output.count - 32_000) < 320, "got \(output.count) samples for 2 s")
        let hertz = Tone.hertz(output)
        #expect(abs(hertz - 1_000) < 20, "tone came out at \(hertz) Hz")
    }

    /// With Keep audio at Medium or High, the same input also reaches the kept recording at its
    /// rate, while the engine still gets 16 kHz.
    @Test func keptOutputGetsTheSameAudioAtItsRate() throws {
        let engine = OSAllocatedUnfairLock(initialState: Data())
        let kept = OSAllocatedUnfairLock(initialState: Data())
        let (format, buffers) = try Tone.second(
            rate: 48_000, channels: 1, interleaved: false, frames: 4096)
        let output = KeptOutput(rate: 24_000) { pcm in kept.withLock { $0.append(pcm) } }
        let onAudio: @Sendable (Data) -> Void = { pcm in engine.withLock { $0.append(pcm) } }
        let tap = try #require(MicrophoneTap(format: format, kept: output, onAudio: onAudio))
        buffers.forEach(tap.receive)
        let heard = Tone.samples(engine.withLock { $0 })
        let keptSamples = Tone.samples(kept.withLock { $0 })
        #expect(abs(heard.count - 16_000) < 160, "the engine got \(heard.count) samples")
        #expect(abs(keptSamples.count - 24_000) < 240, "kept \(keptSamples.count) samples")
        #expect(abs(Tone.hertz(keptSamples, rate: 24_000) - 1_000) < 20)
    }
}

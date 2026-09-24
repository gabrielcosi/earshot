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
}

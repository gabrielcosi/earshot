@preconcurrency import AVFoundation
import Foundation
import Testing

/// Synthetic input for the conversion tests: a 1 kHz tone in the shape a capture delivers it.
enum Tone {
    /// One second of a 1 kHz tone at `rate`, cut into buffers of `frames` frames.
    static func second(
        rate: Double, channels: AVAudioChannelCount, interleaved: Bool, frames: Int
    ) throws -> (AVAudioFormat, [AVAudioPCMBuffer]) {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels,
                interleaved: interleaved))
        let total = Int(rate)
        var buffers: [AVAudioPCMBuffer] = []
        var written = 0
        while written < total {
            let count = min(frames, total - written)
            let buffer = try #require(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            for frame in 0..<count {
                let sample = Float(0.5 * sin(2 * .pi * 1_000 * Double(written + frame) / rate))
                for channel in 0..<Int(channels) {
                    if interleaved {
                        buffer.floatChannelData?[0][frame * Int(channels) + channel] = sample
                    } else {
                        buffer.floatChannelData?[channel][frame] = sample
                    }
                }
            }
            buffers.append(buffer)
            written += count
        }
        return (format, buffers)
    }

    static func samples(_ pcm: Data) -> [Int16] {
        pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map(Int16.init(littleEndian:))
    }

    /// The tone's frequency as heard in `samples` at 16 kHz, from its zero crossings.
    static func hertz(_ samples: [Int16]) -> Int {
        let crossings = zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        return crossings * 16_000 / (2 * max(samples.count, 1))
    }
}

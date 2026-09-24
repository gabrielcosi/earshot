@preconcurrency import AVFoundation
import Foundation

/// A session's audio kept next to its transcript: microphone on the left channel, the Mac's
/// audio on the right, so playback has both sides and later processing can still separate them.
public enum TranscriptAudio {
    /// Speech-grade AAC. Measured: 51 kbit/s for both channels, about 23 MB an hour.
    private static let bitRate = 64_000
    private static let bytesPerSecond = 32_000

    public static func file(for transcript: URL) -> URL {
        transcript.deletingPathExtension().appendingPathExtension("m4a")
    }

    /// Encodes the raw 16 kHz PCM16 recordings, one second at a time so an hour never sits in
    /// memory. The shorter channel is padded with silence.
    public static func encode(microphone: URL?, system: URL, to destination: URL) throws {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2,
                interleaved: false)
        else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: bitRate,
        ]
        let temporary = destination.deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString).m4a")
        let output = try AVAudioFile(
            forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32,
            interleaved: false)
        let left = microphone.flatMap { try? FileHandle(forReadingFrom: $0) }
        let right = try FileHandle(forReadingFrom: system)
        defer {
            try? left?.close()
            try? right.close()
        }
        while true {
            let mic = (try? left?.read(upToCount: bytesPerSecond)) ?? Data()
            let sys = (try? right.read(upToCount: bytesPerSecond)) ?? Data()
            let frames = max(mic.count, sys.count) / 2
            guard frames > 0,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                let channels = buffer.floatChannelData
            else { break }
            buffer.frameLength = AVAudioFrameCount(frames)
            fill(channels[0], frames: frames, from: mic)
            fill(channels[1], frames: frames, from: sys)
            try output.write(from: buffer)
        }
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    }

    private static func fill(_ channel: UnsafeMutablePointer<Float>, frames: Int, from pcm: Data) {
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<frames {
                channel[index] =
                    index < samples.count ? Float(Int16(littleEndian: samples[index])) / 32_768 : 0
            }
        }
    }
}

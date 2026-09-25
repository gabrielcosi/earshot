@preconcurrency import AVFoundation
import EarshotKit
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

    /// The transcript's kept audio, or nil when none was kept. Everything that plays kept audio
    /// finds it here.
    public static func kept(for transcript: URL) -> URL? {
        let audio = file(for: transcript)
        return FileManager.default.fileExists(atPath: audio.path(percentEncoded: false))
            ? audio : nil
    }

    /// The loudest sample of either channel in each of `count` stretches, for the waveform.
    /// Decoded a second at a time, like `encode`, so an hour never sits in memory. Blocking: call
    /// it off the main actor.
    public static func peaks(of audio: URL, count: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: audio)
        let format = file.processingFormat
        let second = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: second) else {
            return []
        }
        var reducer = PeakReducer(frames: Int(file.length), count: count)
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: second)
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { break }
            let frames = Int(buffer.frameLength)
            reducer.add(
                (0..<Int(format.channelCount)).map {
                    UnsafeBufferPointer(start: channels[$0], count: frames)
                })
        }
        return reducer.peaks
    }

    /// Encodes the raw 16 kHz PCM16 recordings, one second at a time so an hour never sits in
    /// memory. The shorter channel is padded with silence.
    public static func encode(microphone: URL?, system: URL, to destination: URL) throws {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2,
                interleaved: false)
        else { return }
        let temporary = destination.deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString).m4a")
        // A failure part way, such as a full disk, would otherwise leave hidden audio behind.
        do {
            try write(microphone: microphone, system: system, format: format, to: temporary)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// The AVAudioFile is closed when this returns, before the file is moved into place.
    private static func write(
        microphone: URL?, system: URL, format: AVAudioFormat, to temporary: URL
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: bitRate,
        ]
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

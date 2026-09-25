@preconcurrency import AVFoundation
import EarshotKit
import Foundation

/// A session's kept audio: microphone on the left channel, the Mac's audio on the right, so
/// later processing can still separate them. Playback and Export Audio… mix both into both ears.
public enum TranscriptAudio {
    /// A raw mono PCM16 recording and its rate.
    public struct Source: Sendable {
        public let url: URL
        public let rate: Double

        public init(url: URL, rate: Double) {
            self.url = url
            self.rate = rate
        }

        init(_ recording: Recording) {
            self.init(url: recording.url, rate: recording.rate)
        }
    }

    /// A transcript's kept audio in `folder`, or nil when none was kept or it is gone. Everything
    /// that plays kept audio finds it here.
    public static func kept(_ name: String?, in folder: URL) -> URL? {
        guard let name else { return nil }
        let audio = folder.appending(path: name)
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

    /// Encodes the raw recordings at the highest rate among them, capped at `quality`, a second at
    /// a time so an hour never sits in memory. The shorter channel is padded with silence.
    public static func encode(
        microphone: Source?, system: Source, quality: AudioQuality, to destination: URL
    ) throws {
        let rates = [system.rate] + (microphone.map { [$0.rate] } ?? [])
        let encoding = AudioQuality.encoding(rates, cappedAt: quality)
        try replace(destination) { temporary in
            try write(microphone: microphone, system: system, as: encoding, to: temporary)
        }
    }

    /// The kept audio mixed into one channel, as the player mixes it, so the file plays in both
    /// ears anywhere. Blocking: call it off the main actor.
    public static func exportMix(of kept: URL, to destination: URL) throws {
        let file = try AVAudioFile(forReading: kept)
        let rate = file.processingFormat.sampleRate
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            throw CaptureError.unsupportedFormat
        }
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(
            .offline, format: mono, maximumFrameCount: renderFrames)
        let player = AVAudioPlayerNode()
        try KeptAudioMix.connect(player, playing: file.processingFormat, in: engine)
        try engine.start()
        defer { engine.stop() }
        player.scheduleFile(file, at: nil)
        player.play()
        // Mono at half the kept file's bitrate: the same bits for each channel.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: AudioQuality.of(rate: rate).bitRate / 2,
        ]
        try replace(destination) { temporary in
            let output = try AVAudioFile(
                forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32,
                interleaved: false)
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: engine.manualRenderingFormat, frameCapacity: renderFrames)
            else { throw CaptureError.unsupportedFormat }
            while engine.manualRenderingSampleTime < file.length {
                let frames = min(
                    AVAudioFrameCount(file.length - engine.manualRenderingSampleTime),
                    renderFrames)
                guard try engine.renderOffline(frames, to: buffer) == .success else {
                    throw CaptureError.unsupportedFormat
                }
                try output.write(from: buffer)
            }
        }
    }

    /// Any size works offline; this is the engine's usual slice.
    private static let renderFrames: AVAudioFrameCount = 4096

    /// Written beside `destination` and moved into place once complete: a failure part way, such
    /// as a full disk, would otherwise leave hidden audio behind. The AVAudioFile `write` opens is
    /// closed when it returns, before the move.
    private static func replace(_ destination: URL, with write: (URL) throws -> Void) throws {
        let temporary = destination.deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString).m4a")
        do {
            try write(temporary)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func write(
        microphone: Source?, system: Source, as quality: AudioQuality, to temporary: URL
    ) throws {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: quality.sampleRate, channels: 2,
                interleaved: false)
        else { throw CaptureError.unsupportedFormat }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: quality.sampleRate,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: quality.bitRate,
        ]
        let output = try AVAudioFile(
            forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32,
            interleaved: false)
        let left = microphone.flatMap { try? ChannelReader($0, rate: quality.sampleRate) }
        let right = try ChannelReader(system, rate: quality.sampleRate)
        let second = AVAudioFrameCount(quality.sampleRate)
        while true {
            let mic = try left?.read(second)
            let sys = try right.read(second)
            let frames = max(mic?.frameLength ?? 0, sys.frameLength)
            guard frames > 0,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                let channels = buffer.floatChannelData
            else { break }
            buffer.frameLength = frames
            copy(mic, to: channels[0], frames: Int(frames))
            copy(sys, to: channels[1], frames: Int(frames))
            try output.write(from: buffer)
        }
    }

    private static func copy(
        _ source: AVAudioPCMBuffer?, to channel: UnsafeMutablePointer<Float>, frames: Int
    ) {
        let available = Int(source?.frameLength ?? 0)
        for index in 0..<frames {
            channel[index] = index < available ? source?.floatChannelData?[0][index] ?? 0 : 0
        }
    }
}

/// One channel's recording at the encoding's rate. One converter carries the whole file, fed
/// until its end, so the resampler's filter runs across every chunk boundary instead of starting
/// over at each one, which would click.
///
/// Unchecked Sendable: the converter's input block is typed Sendable, but it only runs inside
/// `read`, on the caller's thread.
private final class ChannelReader: @unchecked Sendable {
    private let handle: FileHandle
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let converter: AVAudioConverter
    private var ended = false
    private var failure: (any Error)?

    init(_ source: TranscriptAudio.Source, rate: Double) throws {
        guard
            let input = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: source.rate, channels: 1,
                interleaved: false),
            let output = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: input, to: output)
        else { throw CaptureError.unsupportedFormat }
        handle = try FileHandle(forReadingFrom: source.url)
        self.input = input
        self.output = output
        self.converter = converter
    }

    deinit { try? handle.close() }

    /// Up to `frames` frames; fewer only at the end of the recording, and none after it.
    func read(_ frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: frames) else {
            throw CaptureError.unsupportedFormat
        }
        var error: NSError?
        let status = converter.convert(to: buffer, error: &error) { packets, status in
            self.next(packets, status)
        }
        if let failure { throw failure }
        if status == .error { throw error ?? CaptureError.unsupportedFormat }
        return buffer
    }

    private func next(
        _ packets: AVAudioPacketCount, _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        do {
            guard !ended, let pcm = try handle.read(upToCount: Int(packets) * 2),
                pcm.count >= 2,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: input, frameCapacity: AVAudioFrameCount(pcm.count / 2)),
                let channel = buffer.floatChannelData?[0]
            else {
                ended = true
                status.pointee = .endOfStream
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(pcm.count / 2)
            pcm.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                for index in 0..<Int(buffer.frameLength) {
                    channel[index] = Float(Int16(littleEndian: samples[index])) / 32_768
                }
            }
            status.pointee = .haveData
            return buffer
        } catch {
            failure = error
            ended = true
            status.pointee = .endOfStream
            return nil
        }
    }
}

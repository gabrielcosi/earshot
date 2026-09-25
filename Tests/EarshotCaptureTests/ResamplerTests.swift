@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import EarshotCapture

@Suite struct ResamplerTests {
    @Test(arguments: [44_100.0, 48_000.0], [false, true])
    func convertsTapBuffersTo16kMonoAtTheSamePitch(rate: Double, interleaved: Bool) throws {
        let (format, buffers) = try Tone.second(
            rate: rate, channels: 2, interleaved: interleaved, frames: 512)
        let resampler = try #require(Resampler(from: format))
        let output = Tone.samples(buffers.compactMap(resampler.convert).reduce(Data(), +))
        // The converter holds back a filter's worth of samples at the end; 1% covers it.
        #expect(abs(output.count - 16_000) < 160, "got \(output.count) samples for 1 s")
        let hertz = Tone.hertz(output)
        #expect(abs(hertz - 1_000) < 20, "tone came out at \(hertz) Hz")
        #expect(output.map { abs(Int($0)) }.max() ?? 0 > 10_000, "the tone lost its level")
    }

    /// Kept audio at Medium and High is the same capture resampled to their rates instead.
    @Test(arguments: [24_000.0, 48_000.0])
    func convertsTapBuffersToTheKeptRate(rate: Double) throws {
        let (format, buffers) = try Tone.second(
            rate: 44_100, channels: 2, interleaved: false, frames: 512)
        let resampler = try #require(Resampler(from: format, rate: rate))
        let output = Tone.samples(buffers.compactMap(resampler.convert).reduce(Data(), +))
        #expect(abs(Double(output.count) - rate) < rate / 100, "got \(output.count) for 1 s")
        let hertz = Tone.hertz(output, rate: rate)
        #expect(abs(hertz - 1_000) < 20, "tone came out at \(hertz) Hz")
    }
}

@Suite struct TranscriptAudioTests {
    @Test func encodesBothChannelsAtTheLongerLength() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let microphone = directory.appending(path: "mic.pcm")
        let system = directory.appending(path: "sys.pcm")
        try Data(count: 32_000 * 2).write(to: microphone)
        try Data(count: 32_000 * 3).write(to: system)
        let output = directory.appending(path: "transcript.m4a")
        try TranscriptAudio.encode(
            microphone: .init(url: microphone, rate: 16_000),
            system: .init(url: system, rate: 16_000),
            quality: .high, to: output)
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.channelCount == 2)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(abs(Double(file.length) / 16_000 - 3) < 0.1)
    }

    @Test func keptAudioIsFoundOnlyWhenItExists() throws {
        let directory = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(TranscriptAudio.kept(nil, in: directory) == nil)
        #expect(TranscriptAudio.kept("kept.m4a", in: directory) == nil)
        try Data().write(to: directory.appending(path: "kept.m4a"))
        #expect(TranscriptAudio.kept("kept.m4a", in: directory)?.lastPathComponent == "kept.m4a")
    }

    /// A second of silence then a second of tone, on either side: the waveform is flat, then full.
    @Test(arguments: [true, false])
    func peaksFollowTheLouderChannel(toneOnMicrophone: Bool) throws {
        let directory = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let silence = Data(count: 32_000 * 2)
        let tone = Data(count: 32_000) + Self.tone(seconds: 1)
        let microphone = directory.appending(path: "mic.pcm")
        let system = directory.appending(path: "sys.pcm")
        try (toneOnMicrophone ? tone : silence).write(to: microphone)
        try (toneOnMicrophone ? silence : tone).write(to: system)
        let output = directory.appending(path: "transcript.m4a")
        try TranscriptAudio.encode(
            microphone: .init(url: microphone, rate: 16_000),
            system: .init(url: system, rate: 16_000),
            quality: .low, to: output)
        let peaks = try TranscriptAudio.peaks(of: output, count: 4)
        #expect(peaks.count == 4)
        #expect(peaks[0] < 0.1, "silence drew \(peaks)")
        #expect(peaks[3] > 0.9, "the tone drew \(peaks)")
    }

    /// A failed encode, here a system recording that cannot be read, leaves no audio behind.
    @Test func aFailedEncodeLeavesNoFileBehind() throws {
        let directory = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) {
            try TranscriptAudio.encode(
                microphone: nil,
                system: .init(url: directory.appending(path: "missing.pcm"), rate: 16_000),
                quality: .low, to: directory.appending(path: "transcript.m4a"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).isEmpty)
    }

    private static func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A 1 kHz tone at half scale, as the raw 16 kHz PCM16 a session records.
    private static func tone(seconds: Int) -> Data {
        let samples = (0..<(16_000 * seconds)).map { index in
            Int16(16_384 * sin(2 * Double.pi * 1_000 * Double(index) / 16_000)).littleEndian
        }
        return samples.withUnsafeBytes { Data($0) }
    }
}

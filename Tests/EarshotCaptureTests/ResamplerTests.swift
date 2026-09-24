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
        try TranscriptAudio.encode(microphone: microphone, system: system, to: output)
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.channelCount == 2)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(abs(Double(file.length) / 16_000 - 3) < 0.1)
    }
}

@preconcurrency import AVFoundation
import EarshotKit
import Foundation
import Testing

@testable import EarshotCapture

/// What a session records for kept audio, and what is left on disk however it ends.
@Suite struct SessionRecordingsTests {
    /// Keep audio turned off before the session ends: only the system recording naming plays from
    /// stays, and none of the higher-rate audio.
    @Test func turningKeepAudioOffLeavesNoHigherRateFile() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try SessionRecordings(
            microphone: true, keeping: .high, echoCancelled: false, in: directory)
        #expect(recordings.keptSystem?.rate == 48_000)
        #expect(recordings.keptMicrophone?.rate == 48_000)
        for recording in [
            recordings.system, recordings.microphone, recordings.keptSystem,
            recordings.keptMicrophone,
        ] {
            recording?.append(Data(count: 3_200))
        }
        recordings.finish()
        recordings.discardAllButSystem()
        #expect(try Scratch.files(in: directory) == [recordings.system.url.lastPathComponent])
    }

    /// A session that fails to start, or is torn down, leaves nothing.
    @Test func discardLeavesNothing() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try SessionRecordings(
            microphone: true, keeping: .medium, echoCancelled: false, in: directory)
        recordings.discard()
        #expect(try Scratch.files(in: directory).isEmpty)
    }

    /// Keep audio turned on midway: nothing was recorded at a higher rate, so the audio is kept at
    /// the engine's 16 kHz.
    @Test func keepAudioTurnedOnMidwayStaysAt16k() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try SessionRecordings(
            microphone: false, keeping: nil, echoCancelled: false, in: directory)
        #expect(recordings.keptSystem == nil)
        recordings.system.append(Scratch.tone(rate: 16_000, seconds: 1))
        let output = directory.appending(path: "kept.m4a")
        #expect(try recordings.keep(to: output) == nil)
        #expect(try AVAudioFile(forReading: output).fileFormat.sampleRate == 16_000)
    }

    /// The cancelled microphone exists only at 16 kHz; the raw one would carry the echo, so none
    /// is recorded at the higher rate, and the kept file takes the cancelled one.
    @Test func cancelledEchoKeepsTheMicrophoneAt16k() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try SessionRecordings(
            microphone: true, keeping: .high, echoCancelled: true, in: directory)
        #expect(recordings.keptMicrophone == nil)
        #expect(recordings.keptSystem?.rate == 48_000)
        recordings.microphone?.append(Scratch.tone(rate: 16_000, seconds: 1))
        recordings.keptSystem?.append(Scratch.tone(rate: 48_000, seconds: 1))
        let output = directory.appending(path: "kept.m4a")
        #expect(try recordings.keep(to: output) == nil)
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.sampleRate == 48_000)
        let levels = try Scratch.peaks(of: output)
        #expect(levels.allSatisfy { $0 > 0.4 }, "a side is missing: \(levels)")
    }

    /// A write that fails, as on a full disk, is kept as the recording's failure, which decides
    /// what the kept audio is made from.
    @Test func aFailedWriteIsKeptAsTheRecordingsFailure() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = try Scratch.unwritable(in: directory, holding: Data())
        recording.append(Data(count: 3_200))
        recording.append(Data(count: 3_200))
        #expect(recording.failure != nil)
        #expect(try Data(contentsOf: recording.url).isEmpty)
    }

    /// The higher-rate recording stopped early: the channel is kept whole from the engine's.
    @Test func aFailedHigherRateRecordingFallsBackTo16k() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = try Recording(.system, in: directory)
        system.append(Scratch.tone(rate: 16_000, seconds: 2))
        let broken = try Scratch.unwritable(in: directory, holding: Data(), rate: 48_000)
        broken.append(Data(count: 9_600))
        let recordings = SessionRecordings(
            system: system, microphone: nil, keptSystem: broken, keptMicrophone: nil,
            quality: .high)
        let output = directory.appending(path: "kept.m4a")
        #expect(try recordings.keep(to: output) == nil)
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(abs(Double(file.length) / 16_000 - 2) < 0.1)
    }

    /// Both of a channel's recordings stopped early: what they hold is kept, and the failure is
    /// returned so the user hears of it.
    @Test func bothRecordingsFailingKeepsWhatWasWritten() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = try Scratch.unwritable(
            in: directory, holding: Scratch.tone(rate: 16_000, seconds: 1))
        system.append(Data(count: 3_200))
        let broken = try Scratch.unwritable(in: directory, holding: Data(), rate: 48_000)
        broken.append(Data(count: 9_600))
        let recordings = SessionRecordings(
            system: system, microphone: nil, keptSystem: broken, keptMicrophone: nil,
            quality: .high)
        let output = directory.appending(path: "kept.m4a")
        #expect(try recordings.keep(to: output) != nil)
        #expect(abs(Double(try AVAudioFile(forReading: output).length) / 16_000 - 1) < 0.1)
    }
}

@Suite struct KeptEncodingTests {
    /// A 16 kHz microphone next to a system recording at the preset's rate, as with echo
    /// cancellation at Medium or High: the file is at the highest rate recorded, never above the
    /// preset's, both channels run their full length, and neither clicks where one second of the
    /// recording meets the next.
    @Test(arguments: [
        (AudioQuality.high, 48_000.0, 48_000.0), (.medium, 24_000, 24_000),
        (.medium, 48_000, 24_000),
    ])
    func mixedRatesEncodeWithoutSeams(preset: AudioQuality, system rate: Double, expected: Double)
        throws
    {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let microphone = directory.appending(path: "mic.pcm")
        let system = directory.appending(path: "sys.pcm")
        try Scratch.tone(rate: 16_000, seconds: 3).write(to: microphone)
        try Scratch.tone(rate: rate, seconds: 3).write(to: system)
        let output = directory.appending(path: "kept.m4a")
        try TranscriptAudio.encode(
            microphone: .init(url: microphone, rate: 16_000),
            system: .init(url: system, rate: rate), quality: preset, to: output)
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.sampleRate == expected)
        #expect(abs(Double(file.length) / expected - 3) < 0.05)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let second = Int(expected)
        for channel in 0..<2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            func bend(_ index: Int) -> Float {
                abs(samples[index + 1] - 2 * samples[index] + samples[index - 1])
            }
            // How sharply the tone turns next to each second's boundary, against everywhere else:
            // a converter that starts over at a boundary drops what it holds there, and the tone
            // turns sharper (measured with a reset at each second: 1.6 times).
            let seams = [second, 2 * second].flatMap { ($0 - 64)...($0 + 64) }
            let elsewhere = (second / 10..<(3 * second - second / 10)).filter {
                abs($0 - ($0 + second / 2) / second * second) > 64
            }
            let atSeams = seams.map(bend).max() ?? 0
            let normally = elsewhere.map(bend).max() ?? 0
            #expect(
                atSeams <= normally * 1.3,
                "channel \(channel) turns by \(atSeams) at the seams, \(normally) elsewhere")
        }
    }
}

@Suite struct KeptAudioMixTests {
    /// Either side alone plays in both ears, at the level it was recorded at.
    @Test(arguments: [0, 1])
    func eitherSidePlaysInBothEarsAtItsLevel(side: Int) throws {
        let peaks = try Self.render(left: side == 0 ? 0.5 : 0, right: side == 1 ? 0.5 : 0)
        #expect(peaks.allSatisfy { abs($0 - 0.5) < 0.02 }, "ears peaked at \(peaks)")
    }

    /// Both sides loud at once sum past full scale; the limiter holds them under it.
    @Test func bothSidesLoudStayUnderFullScale() throws {
        let peaks = try Self.render(left: 0.8, right: 0.8)
        #expect(peaks.allSatisfy { $0 <= 1 }, "ears peaked at \(peaks)")
    }

    /// A side alone at full scale passes the limiter without being turned down.
    @Test func aLoneSideAtFullScaleIsNotTurnedDown() throws {
        let peaks = try Self.render(left: 0, right: 1)
        #expect(peaks.allSatisfy { $0 >= 0.95 }, "ears peaked at \(peaks)")
    }

    /// Half a second of a 440 Hz tone at the given peak on each side, through the mix; the peak
    /// of each ear.
    private static func render(left: Float, right: Float) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_800)
        let player = AVAudioPlayerNode()
        try KeptAudioMix.connect(player, playing: format, in: engine)
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000))
        input.frameLength = 24_000
        for index in 0..<24_000 {
            let tone = Float(sin(2 * Double.pi * 440 * Double(index) / 48_000))
            input.floatChannelData?[0][index] = left * tone
            input.floatChannelData?[1][index] = right * tone
        }
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(input)
        player.play()
        let output = try #require(
            AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_800))
        var peaks: [Float] = [0, 0]
        for _ in 0..<4 {
            #expect(try engine.renderOffline(4_800, to: output) == .success)
            for channel in 0..<2 {
                for index in 0..<Int(output.frameLength) {
                    peaks[channel] = max(
                        peaks[channel], abs(output.floatChannelData?[channel][index] ?? 0))
                }
            }
        }
        return peaks
    }

    /// Export Audio… writes the mix: one channel, as long as the kept file, at the level heard.
    @Test func exportWritesTheMixInOneChannel() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = try Scratch.kept(in: directory)
        let exported = directory.appending(path: "export.m4a")
        try TranscriptAudio.exportMix(of: kept, to: exported)
        let file = try AVAudioFile(forReading: exported)
        #expect(file.fileFormat.channelCount == 1)
        #expect(abs(Double(file.length) - Double(try AVAudioFile(forReading: kept).length)) < 1_024)
        // A side alone plays at its own level: the tone's 0.5 peak is 0.354 RMS. RMS, since AAC's
        // ringing moves a tone's peaks.
        let level = try Scratch.rms(of: exported)
        #expect(abs(level - 0.354) < 0.03, "the mix came out at \(level) RMS")
    }
}

@MainActor @Suite struct KeptAudioPlayerTests {
    /// Dragging the waveform past its end, or VoiceOver's increment on the last line, seeks to
    /// the very end while playing: that is the end of playback, not a segment of no frames.
    @Test func seekingToTheEndWhilePlayingEndsPlayback() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = try Scratch.kept(in: directory)
        let (player, _) = try Self.offline(kept)
        var ended = false
        player.onEnd = { ended = true }
        #expect(player.play())
        player.seek(to: player.duration)
        #expect(ended)
        #expect(!player.isPlaying)
        #expect(player.currentTime == 0)
    }

    /// A line past the end of audio kept only in part plays nothing, rather than the start.
    @Test func playingPastTheEndDoesNothing() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (player, _) = try Self.offline(Scratch.kept(in: directory))
        player.seek(to: 0.5)
        #expect(!player.play(from: player.duration + 1))
        #expect(!player.isPlaying)
        #expect(player.currentTime == 0.5)
    }

    /// The time follows what was rendered from where playback was moved to, and holds on pause.
    @Test func timeFollowsPlaybackAndHoldsOnPause() throws {
        let directory = try Scratch.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (player, engine) = try Self.offline(Scratch.kept(in: directory))
        #expect(player.play())
        player.seek(to: 1)
        let output = try #require(
            AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 8_000))
        #expect(try engine.renderOffline(8_000, to: output) == .success)
        #expect(abs(player.currentTime - 1.5) < 0.01, "at \(player.currentTime)")
        player.pause()
        #expect(abs(player.currentTime - 1.5) < 0.01, "paused at \(player.currentTime)")
    }

    private static func offline(_ kept: URL) throws -> (KeptAudioPlayer, AVAudioEngine) {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2))
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 8_000)
        return (try #require(KeptAudioPlayer(audio: kept, engine: engine)), engine)
    }
}

enum Scratch {
    static func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func files(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
    }

    /// A 1 kHz tone at half scale, as the raw PCM16 a capture records at `rate`.
    static func tone(rate: Double, seconds: Int) -> Data {
        let samples = (0..<(Int(rate) * seconds)).map { index in
            Int16(16_384 * sin(2 * Double.pi * 1_000 * Double(index) / rate)).littleEndian
        }
        return samples.withUnsafeBytes { Data($0) }
    }

    /// A recording whose writes fail, as on a full disk, after `holding` was written.
    static func unwritable(in directory: URL, holding: Data, rate: Double = 16_000) throws
        -> Recording
    {
        let url = directory.appending(path: "\(UUID().uuidString).pcm")
        try holding.write(to: url)
        return Recording(url: url, rate: rate, handle: try FileHandle(forReadingFrom: url))
    }

    /// The first channel's RMS level over the middle half.
    static func rms(of audio: URL) throws -> Float {
        let file = try AVAudioFile(forReading: audio)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = try #require(buffer.floatChannelData?[0])
        let middle = (Int(buffer.frameLength) / 4)..<(Int(buffer.frameLength) * 3 / 4)
        return sqrt(middle.map { samples[$0] * samples[$0] }.reduce(0, +) / Float(middle.count))
    }

    /// Two seconds of kept audio: silence on the microphone's side, a tone on the Mac's.
    static func kept(in directory: URL) throws -> URL {
        let microphone = directory.appending(path: "mic.pcm")
        let system = directory.appending(path: "sys.pcm")
        try Data(count: 32_000 * 2).write(to: microphone)
        try tone(rate: 16_000, seconds: 2).write(to: system)
        let kept = directory.appending(path: "kept.m4a")
        try TranscriptAudio.encode(
            microphone: .init(url: microphone, rate: 16_000),
            system: .init(url: system, rate: 16_000), quality: .low, to: kept)
        return kept
    }

    /// The loudest sample of each channel.
    static func peaks(of audio: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: audio)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return (0..<Int(file.processingFormat.channelCount)).map { channel in
            (0..<Int(buffer.frameLength)).map { abs(buffer.floatChannelData?[channel][$0] ?? 0) }
                .max() ?? 0
        }
    }
}

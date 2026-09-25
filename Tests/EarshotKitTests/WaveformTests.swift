import Foundation
import Testing

@testable import EarshotKit

extension PeakReducer {
    fileprivate mutating func add(_ samples: [Float]...) {
        let buffers = samples.map { channel in
            let copy = UnsafeMutableBufferPointer<Float>.allocate(capacity: channel.count)
            _ = copy.initialize(from: channel)
            return UnsafeBufferPointer(copy)
        }
        defer { buffers.forEach { $0.deallocate() } }
        add(buffers)
    }
}

@Suite struct WaveformTests {
    /// Each peak is the loudest sample in its stretch of the audio, relative to the loudest of
    /// all, so a quiet recording still draws a waveform.
    @Test func peaksAreTheLoudestSampleOfEachStretch() {
        var reducer = PeakReducer(frames: 8, count: 4)
        reducer.add([0.1, -0.2, 0, 0, 0.05, 0.1, -0.4, 0.1])
        #expect(reducer.peaks == [0.5, 0, 0.25, 1])
    }

    /// The file is read a chunk at a time; where the chunks break changes nothing.
    @Test func chunksDoNotChangeThePeaks() {
        let samples: [Float] = (0..<1_000).map { Float(sin(Double($0) / 7)) * Float($0 % 13) }
        var whole = PeakReducer(frames: samples.count, count: 30)
        whole.add(samples)
        var chunked = PeakReducer(frames: samples.count, count: 30)
        for start in stride(from: 0, to: samples.count, by: 77) {
            chunked.add(Array(samples[start..<min(start + 77, samples.count)]))
        }
        #expect(chunked.peaks == whole.peaks)
    }

    /// Audio shorter than the peaks asked for gets a peak per frame, none of them empty.
    @Test func shortAudioHasAPeakPerFrame() {
        var reducer = PeakReducer(frames: 3, count: 10)
        reducer.add([0.5, 1, 0.25])
        #expect(reducer.peaks == [0.5, 1, 0.25])
        #expect(PeakReducer(frames: 0, count: 10).peaks.isEmpty)
    }

    /// Frames past the length the file declared land in the last peak rather than trapping.
    @Test func framesPastTheDeclaredLengthLandInTheLastPeak() {
        var reducer = PeakReducer(frames: 4, count: 2)
        reducer.add([0.1, 0.1, 0.1, 0.2, 0.8])
        #expect(reducer.peaks == [0.125, 1])
    }

    /// Microphone and the Mac's audio are separate channels; either one speaking draws.
    @Test func aFrameIsAsLoudAsItsLoudestChannel() {
        var reducer = PeakReducer(frames: 4, count: 2)
        reducer.add([0.8, 0, 0, 0], [0, 0, 0, 0.4])
        #expect(reducer.peaks == [1, 0.5])
    }

    @Test func silenceDrawsFlat() {
        var reducer = PeakReducer(frames: 4, count: 2)
        reducer.add([0, 0, 0, 0])
        #expect(reducer.peaks == [0, 0])
    }

    /// Drawn narrower than the peaks, each bar keeps the loudest peak it covers.
    @Test func barsKeepTheLoudestPeakTheyCover() {
        let peaks: [Float] = [0.1, 0.9, 0.2, 0.3, 1, 0.4]
        #expect(Waveform.bars(peaks, count: 3) == [0.9, 0.3, 1])
        #expect(Waveform.bars(peaks, count: 4) == [0.9, 0.2, 1, 0.4])
        #expect(Waveform.bars(peaks, count: 6) == peaks)
        #expect(Waveform.bars(peaks, count: 0).isEmpty)
    }

    /// Wider than the peaks, the waveform stretches them rather than going flat at the end.
    @Test func barsRepeatPeaksWhenWider() {
        #expect(Waveform.bars([0.2, 1], count: 4) == [0.2, 0.2, 1, 1])
        #expect(Waveform.bars([], count: 4).isEmpty)
    }
}

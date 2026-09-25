/// Reduces audio to the peaks a waveform draws, a chunk at a time, so an hour of audio never sits
/// in memory: each peak is the loudest sample in its equal stretch of the audio.
public struct PeakReducer: Sendable {
    private let frames: Int
    private var loudest: [Float]
    private var frame = 0

    /// `frames` is the audio's length; a peak covers at least one frame.
    public init(frames: Int, count: Int) {
        self.frames = frames
        loudest = Array(repeating: 0, count: max(0, min(count, frames)))
    }

    /// The next frames, one buffer per channel; a frame's level is its loudest channel.
    public mutating func add(_ channels: [UnsafeBufferPointer<Float>]) {
        guard !loudest.isEmpty, let length = channels.map(\.count).min() else { return }
        var start = 0
        while start < length {
            let peak = min(frame * loudest.count / frames, loudest.count - 1)
            let end =
                peak == loudest.count - 1
                ? length : min(length, start + firstFrame(of: peak + 1) - frame)
            var level = loudest[peak]
            for channel in channels {
                for index in start..<end { level = max(level, abs(channel[index])) }
            }
            loudest[peak] = level
            frame += end - start
            start = end
        }
    }

    /// The first frame whose peak is `peak`: frame f belongs to peak f × count / frames.
    private func firstFrame(of peak: Int) -> Int {
        (peak * frames + loudest.count - 1) / loudest.count
    }

    /// Relative to the loudest, so a quiet recording still draws a waveform.
    public var peaks: [Float] {
        let top = loudest.max() ?? 0
        return top > 0 ? loudest.map { $0 / top } : loudest
    }
}

public enum Waveform {
    /// The peaks fitted to `count` bars: narrower, each bar keeps the loudest peak it covers;
    /// wider, neighbouring bars repeat a peak.
    public static func bars(_ peaks: [Float], count: Int) -> [Float] {
        guard count > 0, !peaks.isEmpty else { return [] }
        guard count < peaks.count else {
            return (0..<count).map { peaks[$0 * peaks.count / count] }
        }
        var bars = [Float](repeating: 0, count: count)
        for (index, peak) in peaks.enumerated() {
            let bar = index * count / peaks.count
            bars[bar] = max(bars[bar], peak)
        }
        return bars
    }
}

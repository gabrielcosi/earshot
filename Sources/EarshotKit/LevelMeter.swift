import Foundation
import os

/// How loud a capture has been lately, for its level meter. Fed 16 kHz mono PCM16 on the
/// capture's thread and read by the interface: the RMS level of each of the latest whole windows,
/// on a scale from `floor` to full scale.
public final class LevelMeter: Sendable {
    /// A syllable lasts about 200 ms in conversation (four to five a second), so a window of half
    /// that rises and falls with each syllable, as a meter watched for speech should.
    public static let window = Duration.milliseconds(100)
    /// The bottom of the scale, under the room noise measured for `EchoCanceller` (a room's
    /// speakers' echo at -55 to -58 dBFS was below it): a quiet room still moves the meter a
    /// little, and only digital silence leaves it empty.
    static let floor = -60.0
    /// The meter's bars, one a window: the last second.
    public static let history = 10
    private static let windowSamples = Int(window / .seconds(1) * Double(PCM.bytesPerSecond / 2))

    private struct State {
        var sumOfSquares = 0.0
        var samples = 0
        var levels = Array(repeating: 0.0, count: LevelMeter.history)
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    /// The latest `history` windows, oldest first, each from 0, at or under `floor`, to 1 at full
    /// scale; 0 for windows not yet heard.
    public var levels: [Double] { state.withLock(\.levels) }

    /// A window ends with the buffer that completes it: the process tap and the echo canceller
    /// hand over 10 ms at a time and the microphone alone about 85 ms, so a window runs 100 to
    /// 170 ms.
    public func add(_ pcm: Data) {
        let (sumOfSquares, count) = pcm.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).reduce(into: (0.0, 0)) { total, sample in
                let value = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                total.0 += value * value
                total.1 += 1
            }
        }
        state.withLock { state in
            state.sumOfSquares += sumOfSquares
            state.samples += count
            guard state.samples >= Self.windowSamples else { return }
            state.levels.removeFirst()
            state.levels.append(
                Self.scaled(
                    rms: (state.sumOfSquares / Double(state.samples)).squareRoot()))
            state.sumOfSquares = 0
            state.samples = 0
        }
    }

    private static func scaled(rms: Double) -> Double {
        guard rms > 0 else { return 0 }
        return min(max((20 * log10(rms) - floor) / -floor, 0), 1)
    }
}

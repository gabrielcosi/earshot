import Foundation
import Testing

@testable import EarshotKit

@Suite struct LevelMeterTests {
    /// A square wave of `amplitude` at 16 kHz: its RMS level is the amplitude.
    private func square(amplitude: Double, milliseconds: Int) -> Data {
        let value = Int16(amplitude * Double(Int16.max))
        let samples = (0..<(16 * milliseconds)).map { index in
            (index / 8).isMultiple(of: 2) ? value : -value
        }
        return samples.withUnsafeBytes { Data($0) }
    }

    @Test func aSquareWaveAtMinus20DBFSFillsTwoThirdsOfTheScale() {
        let meter = LevelMeter()
        meter.add(square(amplitude: 0.1, milliseconds: 100))
        #expect(abs((meter.levels.last ?? -1) - 40.0 / 60.0) < 0.01)
    }

    @Test func fullScaleFillsTheMeter() {
        let meter = LevelMeter()
        meter.add(square(amplitude: 1, milliseconds: 100))
        #expect((meter.levels.last ?? -1) > 0.99)
    }

    @Test func silenceAfterSoundEmptiesItWithinAWindow() {
        let meter = LevelMeter()
        meter.add(square(amplitude: 0.5, milliseconds: 100))
        meter.add(square(amplitude: 0, milliseconds: 100))
        #expect((meter.levels.last ?? -1) == 0)
    }

    @Test func soundUnderTheFloorShowsNothing() {
        let meter = LevelMeter()
        meter.add(square(amplitude: 0.0005, milliseconds: 100))
        #expect((meter.levels.last ?? -1) == 0)
    }

    /// The tap delivers about 10 ms at a time; the level waits for a whole window.
    @Test func itWaitsForAWholeWindowAcrossBuffers() {
        let meter = LevelMeter()
        let buffer = square(amplitude: 0.1, milliseconds: 10)
        for _ in 0..<9 { meter.add(buffer) }
        #expect((meter.levels.last ?? -1) == 0)
        meter.add(buffer)
        #expect((meter.levels.last ?? -1) > 0.6)
    }

    /// The meter draws the last second, newest on the right.
    @Test func itKeepsTheLastSecondOldestFirst() {
        let meter = LevelMeter()
        meter.add(square(amplitude: 1, milliseconds: 100))
        meter.add(square(amplitude: 0.1, milliseconds: 100))
        let levels = meter.levels
        #expect(levels.count == 10)
        #expect(levels.prefix(8).allSatisfy { $0 == 0 })
        #expect(levels[8] > 0.99)
        #expect(abs(levels[9] - 40.0 / 60.0) < 0.01)
    }
}

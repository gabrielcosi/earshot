import Foundation
import Testing

@testable import EarshotCapture

/// 16 kHz PCM16 signals for the canceller tests, and the arithmetic to judge its output.
enum Signal {
    static func fixture(_ name: String) throws -> [Int16] {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "wav"))
        return samples(try Data(contentsOf: url).dropFirst(44))
    }

    static func samples(_ pcm: Data) -> [Int16] {
        pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map(Int16.init(littleEndian:))
    }

    static func pcm(_ samples: [Int16]) -> Data {
        samples.map(\.littleEndian).withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// `signal` heard `delay` samples later at `gain`, as a room hears the speakers.
    static func echo(of signal: [Int16], delay: Int, gain: Float) -> [Int16] {
        [Int16](repeating: 0, count: delay) + signal.map { Int16(Float($0) * gain) }
    }

    static func mix(_ first: [Int16], _ second: [Int16], at offset: Int = 0) -> [Int16] {
        var mixed = first
        for (index, sample) in second.enumerated() where index + offset < mixed.count {
            mixed[index + offset] = Int16(clamping: Int(mixed[index + offset]) + Int(sample))
        }
        return mixed
    }

    static func dbfs(_ samples: ArraySlice<Int16>) -> Double {
        let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return 10 * log10(max(energy / Double(max(samples.count, 1)), 1) / (32_768 * 32_768))
    }

    /// The best normalized cross-correlation of `output` against `reference` with the output
    /// up to `maxLag` samples late; 1 is the same waveform at any level. AEC3's filters delay
    /// the near end by a few milliseconds, so zero lag alone would miss a preserved signal.
    static func correlation(
        _ output: ArraySlice<Int16>, _ reference: ArraySlice<Int16>, maxLag: Int
    ) -> (value: Double, lag: Int) {
        let out = Array(output)
        let ref = Array(reference)
        let count = min(ref.count, out.count - maxLag)
        let refEnergy = ref[..<count].reduce(0.0) { $0 + Double($1) * Double($1) }
        var best = (value: -1.0, lag: 0)
        for lag in 0...maxLag {
            var dot = 0.0
            var outEnergy = 0.0
            for index in 0..<count {
                let sample = Double(out[index + lag])
                dot += sample * Double(ref[index])
                outEnergy += sample * sample
            }
            let value = dot / max(sqrt(outEnergy * refEnergy), 1)
            if value > best.value { best = (value, lag) }
        }
        return best
    }

    /// The process tap's buffers after resampling: 171 samples.
    static let tapChunk = 342
    /// AVAudioEngine's input tap after resampling: 100 ms.
    static let microphoneChunk = 3200
    /// The tap leads the microphone by 90 to 100 ms (measured: 4096-frame tap buffer plus device
    /// latencies), so the echo of a far-end sample arrives 100 ms after the sample was fed.
    static let echoDelay = 1_600

    /// Feeds both streams as the captures deliver them: the far end in tap-sized chunks as it
    /// plays, the microphone in 100 ms chunks, each one after the far end it echoes.
    static func cancel(far: [Int16], microphone: [Int16]) throws -> [Int16] {
        let canceller = try #require(EchoCanceller())
        var output: [Int16] = []
        var fed = 0
        var heard = 0
        while heard < microphone.count {
            let until = min(heard + Self.microphoneChunk, microphone.count)
            while fed < min(until - Self.echoDelay + Self.tapChunk / 2, far.count) {
                let end = min(fed + Self.tapChunk / 2, far.count)
                canceller.feedFarEnd(Signal.pcm(Array(far[fed..<end])))
                fed = end
            }
            output += Signal.samples(
                canceller.process(Signal.pcm(Array(microphone[heard..<until]))))
            heard = until
        }
        return output
    }
}

@Suite struct EchoCancellerTests {
    @Test func keepsEveryBlockInOrderAcrossOddChunkSizes() throws {
        let canceller = try #require(EchoCanceller())
        let tone = (0..<16_000).map { Int16(16_000 * sin(2 * .pi * 1_000 * Double($0) / 16_000)) }
        var output: [Int16] = []
        var chunks: [Int] = []
        var offset = 0
        while offset < tone.count {
            let end = min(offset + Signal.tapChunk / 2, tone.count)
            let cleaned = canceller.process(Signal.pcm(Array(tone[offset..<end])))
            chunks.append(cleaned.count)
            output += Signal.samples(cleaned)
            offset = end
        }
        #expect(chunks.allSatisfy { $0.isMultiple(of: EchoCanceller.blockBytes) })
        #expect(tone.count - output.count < EchoCanceller.blockBytes / 2)
        #expect(abs(Tone.hertz(output) - 1_000) < 20, "tone came out at \(Tone.hertz(output)) Hz")
        let level = Signal.dbfs(output[8_000...]) - Signal.dbfs(tone[8_000...])
        print("no far end: level \(level) dB, chunks \(Set(chunks).sorted())")
        #expect(abs(level) < 1, "the tone changed level by \(level) dB with nothing to cancel")
    }

    @Test func cancelsTheSpeakersFromTheMicrophone() throws {
        let far = try Signal.fixture("two-speakers")
        let microphone = Signal.echo(of: far, delay: Signal.echoDelay, gain: 0.1)
        let output = try Signal.cancel(far: far, microphone: microphone)
        let settled = output.count / 2..<output.count
        let before = Signal.dbfs(microphone[settled])
        let after = Signal.dbfs(output[settled])
        print("echo: \(before) dBFS -> \(after) dBFS, reduction \(before - after) dB")
        // A room's speakers measured 27 to 30 dB of reduction; this straight copy gives 49 dB.
        // At 20 dB the bleed in that room would already sit under its noise floor.
        #expect(before - after > 20, "echo only fell by \(before - after) dB")
    }

    @Test func keepsTheNearEndDuringDoubleTalk() throws {
        let far = try Signal.fixture("two-speakers")
        let near = try Signal.fixture("names")
        let echo = Signal.echo(of: far, delay: Signal.echoDelay, gain: 0.1)
        let start = 6 * 16_000
        let microphone = Signal.mix(echo, near, at: start)
        let output = try Signal.cancel(far: far, microphone: microphone)
        let region = start..<min(start + near.count, output.count)
        // Two seconds of the near end, allowed one AEC3 block late (measured: 8 ms).
        let correlation = Signal.correlation(
            output[start..<start + 32_160], near[0..<32_000], maxLag: 160)
        let alone = try Signal.cancel(far: [], microphone: near)
        let ceiling = Signal.correlation(alone[0..<32_160], near[0..<32_000], maxLag: 160)
        let level = Signal.dbfs(output[region]) - Signal.dbfs(near[0..<region.count])
        print("near end: correlation \(correlation), alone \(ceiling), level \(level) dB")
        // Measured 0.71 here and 0.74 on a room recording, against 0.79 with no far end at all
        // (the high-pass filter reshapes the waveform; the suppressor trims it in double talk). Residual echo alone
        // correlates near 0, so half the measured value still tells the two apart.
        #expect(correlation.value > 0.35)
        #expect(abs(level) < 3)
    }
}

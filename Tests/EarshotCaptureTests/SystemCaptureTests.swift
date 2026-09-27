@preconcurrency import AVFoundation
import EarshotKit
import Foundation
import Testing
import os

@testable import EarshotCapture

/// The real process tap. Plays a clip through the Mac's output and captures it, so it makes
/// sound and needs the audio-capture permission for the app running the tests (Terminal).
/// Serialized: each test would hear the other's sound through the global tap.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["EARSHOT_CAPTURE"] == "1"))
struct SystemCaptureTests {
    @Test func capturesWhatThisMacPlaysAtRealTime() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/two-speakers", withExtension: "wav"))
        let captured = OSAllocatedUnfairLock(initialState: Data())
        let capture = SystemAudioCapture()
        try capture.start { pcm in captured.withLock { $0.append(pcm) } }
        let player = try AVAudioPlayer(contentsOf: url)
        let clock = ContinuousClock()
        let started = clock.now
        player.play()
        try await Task.sleep(for: .seconds(player.duration + 0.5))
        capture.stop()
        let elapsed = (clock.now - started) / .seconds(1)

        let pcm = captured.withLock { $0 }
        let seconds = Double(pcm.count) / 32_000
        // A tap reading its rate wrong delivers 8% too little or too much: 44.1 vs 48 kHz.
        #expect(abs(seconds - elapsed) / elapsed < 0.03, "captured \(seconds) s in \(elapsed) s")
        let peak = pcm.withUnsafeBytes {
            $0.bindMemory(to: Int16.self).map { abs(Int(Int16(littleEndian: $0))) }.max() ?? 0
        }
        #expect(
            peak > 1_000, "the capture is silent (peak \(peak)): check the audio-capture permission"
        )
    }

    /// Setup's check: the ding Earshot plays itself reaches the global tap every session uses,
    /// and the check stops as soon as it arrives, before the ding ends. Prints how long after
    /// the tap's first buffer that was.
    @Test func hearsTheDingThisProcessPlays() async throws {
        let pcm = try await SystemAudioCheck.listen()

        #expect(!PCM.isSilent(pcm), "the tap heard only zeros: check the audio-capture permission")
        let samples = Tone.samples(pcm)
        let first = try #require(samples.firstIndex { $0 != 0 })
        print("the ding reached the tap \(Double(first) / 16_000) s after its first buffer")
        let listened = Double(samples.count) / 16_000
        let length = try AVAudioPlayer(contentsOf: SystemAudioCheck.ding).duration
        #expect(listened < length, "listened \(listened) s: it should stop once it hears the ding")
    }
}

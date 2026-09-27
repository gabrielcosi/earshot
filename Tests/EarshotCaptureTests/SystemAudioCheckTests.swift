import EarshotKit
import Foundation
import Testing

@testable import EarshotCapture

/// The ding check's listening window, fed buffers by hand instead of the tap.
@Suite struct SystemAudioCheckTests {
    /// A buffer of 10 ms of 16 kHz PCM16, all zeros or with one sample above zero.
    private func buffer(silent: Bool) -> Data {
        var pcm = Data(count: 320)
        if !silent { pcm[100] = 1 }
        return pcm
    }

    /// The tap delivers before the ding plays, then the ding arrives: the window stays open for
    /// the ding's length after the first buffer, not only until it.
    @Test func hearsWhatArrivesWhileTheSoundPlays() async {
        let (buffers, delivery) = AsyncStream.makeStream(of: Data.self)
        delivery.yield(buffer(silent: true))
        let heard = await SystemAudioCheck.collect(
            buffers, delivery, firstBufferTimeout: .seconds(2)
        ) {
            // The tap's buffers come every ~10 ms; 100 ms after the start is well inside a
            // one-second sound, and well after the first buffer.
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                delivery.yield(buffer(silent: false))
            }
            return .seconds(1)
        }
        #expect(!PCM.isSilent(heard))
    }

    /// A denied tap delivers zeros on schedule: the window closes when the sound has played.
    @Test func zerosThroughoutAreSilent() async {
        let (buffers, delivery) = AsyncStream.makeStream(of: Data.self)
        let silence = buffer(silent: true)
        delivery.yield(silence)
        let heard = await SystemAudioCheck.collect(
            buffers, delivery, firstBufferTimeout: .seconds(2)
        ) {
            delivery.yield(silence)
            return .milliseconds(50)
        }
        #expect(PCM.isSilent(heard))
        #expect(heard.count == 2 * silence.count)
    }
}

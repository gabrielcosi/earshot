@preconcurrency import AVFoundation
import EarshotCapture
import Foundation
import Observation

/// Plays one line of a transcript at a time, from kept audio, both sides in both ears, or from the
/// recording of the session that just ended, which holds one side already.
@Observable
final class ClipPlayer {
    private(set) var playing: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var kept: KeptAudioPlayer?
    @ObservationIgnored private var ending: Task<Void, Never>?

    func toggle(_ id: String, file: URL, from start: Double, seconds: Double) {
        guard begin(id) else { return }
        guard let kept = KeptAudioPlayer(audio: file) else { return stop() }
        guard kept.play(from: start) else { return stop() }
        self.kept = kept
        end(id, after: seconds)
    }

    func toggle(_ id: String, clip: Data?) {
        guard begin(id) else { return }
        guard let clip, let player = try? AVAudioPlayer(data: clip) else { return stop() }
        self.player = player
        player.play()
        end(id, after: player.duration)
    }

    func stop() {
        ending?.cancel()
        player?.stop()
        player = nil
        kept?.stop()
        kept = nil
        playing = nil
    }

    /// Stops what is playing; false when that was the same line, which is a toggle off.
    private func begin(_ id: String) -> Bool {
        let same = playing == id
        stop()
        return !same
    }

    private func end(_ id: String, after seconds: Double) {
        playing = id
        ending = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, playing == id { stop() }
        }
    }
}

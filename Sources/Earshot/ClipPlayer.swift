@preconcurrency import AVFoundation
import Foundation
import Observation

/// Plays one line of a transcript at a time, from saved audio or from the recording of the session
/// that just ended.
@Observable
final class ClipPlayer {
    private(set) var playing: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ending: Task<Void, Never>?

    func toggle(_ id: String, file: URL, from start: Double, seconds: Double) {
        guard begin(id) else { return }
        guard let player = try? AVAudioPlayer(contentsOf: file) else { return stop() }
        player.currentTime = start
        run(player, id: id, seconds: seconds)
    }

    func toggle(_ id: String, clip: Data?) {
        guard begin(id) else { return }
        guard let clip, let player = try? AVAudioPlayer(data: clip) else { return stop() }
        run(player, id: id, seconds: player.duration)
    }

    func stop() {
        ending?.cancel()
        player?.stop()
        player = nil
        playing = nil
    }

    /// Stops what is playing; false when that was the same line, which is a toggle off.
    private func begin(_ id: String) -> Bool {
        let same = playing == id
        stop()
        return !same
    }

    private func run(_ player: AVAudioPlayer, id: String, seconds: Double) {
        self.player = player
        playing = id
        player.play()
        ending = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, playing == id { stop() }
        }
    }
}

import EarshotCapture
import EarshotKit
import Foundation
import Observation

/// Plays a saved transcript's kept audio from any point, both sides in both ears, for the player
/// above the transcript and the cards' Play from Here.
@Observable
final class TranscriptPlayer {
    let duration: Double
    /// Empty until read from the file, or when it cannot be read: the waveform then draws flat.
    private(set) var peaks: [Float] = []
    private(set) var isPlaying = false
    /// Where playback is, updated when it is moved, paused, or reaches a line's start or the end,
    /// which is all the cards need; the player's own bar redraws from `currentTime` as it plays.
    private(set) var time: Double = 0
    /// Where each line starts, to know when the line being played changes.
    @ObservationIgnored var starts: [Double] = []
    private let player: KeptAudioPlayer
    private let audio: URL
    @ObservationIgnored private var watching: Task<Void, Never>?

    /// Read once per file and fitted to the width drawn. The widest waveform, on a 6K display's
    /// 3008 points less the sidebar and the player's controls, is under 3000 points, which at
    /// `WaveformView.barPitch` is under 1000 bars: no bar is ever stretched over two peaks.
    nonisolated private static let peakCount = 1000

    init?(audio: URL) {
        guard let player = KeptAudioPlayer(audio: audio) else { return nil }
        self.player = player
        self.audio = audio
        duration = player.duration
        player.onEnd = { [weak self] in self?.ended() }
    }

    var currentTime: Double { isPlaying ? player.currentTime : time }

    /// Measured on an hour of kept audio: 0.48 s, 0.41 s of it decoding, so it is not cached.
    func loadPeaks() async {
        peaks = await Self.peaks(of: audio)
    }

    @concurrent
    nonisolated private static func peaks(of audio: URL) async -> [Float] {
        (try? TranscriptAudio.peaks(of: audio, count: peakCount)) ?? []
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    /// Nothing happens past the end of audio kept only in part.
    func play(from start: Double) {
        guard player.play(from: start) else { return }
        time = player.currentTime
        isPlaying = true
        watch()
    }

    func seek(to position: Double) {
        player.seek(to: position)
        time = player.currentTime
        if isPlaying { watch() }
    }

    func pause() {
        watching?.cancel()
        player.pause()
        isPlaying = false
        time = player.currentTime
    }

    /// Pauses and lets the audio output go, when the transcript is no longer shown.
    func close() {
        pause()
        player.stop()
    }

    private func play() {
        guard player.play() else { return }
        isPlaying = true
        watch()
    }

    /// Back to the start at the end, as players do; where it was when the output failed.
    private func ended() {
        watching?.cancel()
        isPlaying = false
        time = player.currentTime
    }

    /// Wakes where the line being played changes, rather than polling, so the cards move on at
    /// each line's start. After the last line's start it stops: the end comes from the player.
    private func watch() {
        watching?.cancel()
        watching = Task { [weak self] in
            while let self, self.player.isPlaying, !Task.isCancelled {
                self.time = self.player.currentTime
                let next = Playback.nextChange(
                    after: self.time, starts: self.starts, duration: self.duration)
                guard next < self.duration else { return }
                try? await Task.sleep(for: .seconds(next - self.time))
            }
        }
    }
}

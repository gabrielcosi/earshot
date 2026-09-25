@preconcurrency import AVFoundation
import EarshotCapture
import EarshotKit
import Foundation
import Observation

/// Plays a saved transcript's kept audio from any point, for the player above the transcript and
/// the cards' Play from Here.
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
    private let player: AVAudioPlayer
    private let audio: URL
    @ObservationIgnored private var watching: Task<Void, Never>?

    /// Read once per file and fitted to the width drawn. The widest waveform, on a 6K display's
    /// 3008 points less the sidebar and the player's controls, is under 3000 points, which at
    /// `WaveformView.barPitch` is under 1000 bars: no bar is ever stretched over two peaks.
    nonisolated private static let peakCount = 1000

    init?(audio: URL) {
        guard let player = try? AVAudioPlayer(contentsOf: audio) else { return nil }
        self.player = player
        self.audio = audio
        duration = player.duration
        player.prepareToPlay()
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

    func play(from start: Double) {
        seek(to: start)
        play()
    }

    func seek(to position: Double) {
        player.currentTime = min(max(position, 0), duration)
        time = player.currentTime
        if isPlaying { watch() }
    }

    func pause() {
        watching?.cancel()
        player.pause()
        isPlaying = false
        time = player.currentTime
    }

    private func play() {
        guard player.play() else { return }
        isPlaying = true
        watch()
    }

    /// Wakes where the line being played changes, rather than polling: the cards move on at each
    /// line's start, and the button turns back to Play at the end.
    private func watch() {
        watching?.cancel()
        watching = Task { [weak self] in
            while let self, self.player.isPlaying, !Task.isCancelled {
                self.time = self.player.currentTime
                let next = Playback.nextChange(
                    after: self.time, starts: self.starts, duration: self.duration)
                try? await Task.sleep(for: .seconds(next - self.time))
            }
            guard !Task.isCancelled, let self else { return }
            // AVAudioPlayer that plays to the end reports the time it last started from, not the
            // end; back to the start, as players do, rather than to that line.
            self.player.currentTime = 0
            self.isPlaying = false
            self.time = 0
        }
    }
}

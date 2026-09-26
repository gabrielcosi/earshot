import EarshotKit
import SwiftUI

/// The kept audio above a saved transcript: play and pause, the waveform to seek in, and the time.
struct PlayerBar: View {
    let player: TranscriptPlayer

    var body: some View {
        HStack(spacing: 12) {
            Button(
                player.isPlaying ? "Pause" : "Play",
                systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                action: player.toggle
            )
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
            // Redrawn every frame while playing, and when paused only as the position moves.
            TimelineView(.animation(paused: !player.isPlaying)) { _ in
                let now = player.currentTime
                HStack(spacing: 12) {
                    WaveformView(player: player, position: now)
                    Text(Playback.clock(now, of: player.duration))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .task { await player.loadPeaks() }
    }
}

/// The audio's loudness over time, played part in the accent colour. Clicking or dragging seeks.
struct WaveformView: View {
    let player: TranscriptPlayer
    let position: Double
    @State private var width = 0.0

    /// A 2-point bar and a 1-point gap: the thinnest bars that stay apart on a non-Retina display.
    static let barPitch = 3.0
    private static let barWidth = 2.0
    /// The height of the bars at full level, as tall as the large play button beside them.
    private static let height = 28.0

    var body: some View {
        Canvas { context, size in
            let count = Int(size.width / Self.barPitch)
            // Flat until the peaks are read.
            let bars =
                player.peaks.isEmpty
                ? Array(repeating: 0, count: count) : Waveform.bars(player.peaks, count: count)
            var path = Path()
            for index in 0..<bars.count {
                let barHeight = max(Self.barWidth, CGFloat(bars[index]) * size.height)
                path.addRoundedRect(
                    in: CGRect(
                        x: Double(index) * Self.barPitch, y: (size.height - barHeight) / 2,
                        width: Self.barWidth, height: barHeight),
                    cornerSize: CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2))
            }
            context.fill(path, with: .style(.tertiary))
            // Coloured up to the exact point, through the bar it is in. A bar at a time, the played
            // part of two minutes in a 1,000-point waveform moved on under three times a second.
            let played = Playback.fraction(of: position, in: player.duration) * size.width
            context.clip(to: Path(CGRect(x: 0, y: 0, width: played, height: size.height)))
            context.fill(path, with: .style(.tint))
        }
        .frame(height: Self.height)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                seek(toX: drag.location.x)
            }
        )
        .onGeometryChange(for: Double.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Playback.spoken(position, of: player.duration))
        .accessibilityAdjustableAction { direction in
            player.seek(
                to: Playback.step(
                    from: player.currentTime, forward: direction == .increment,
                    starts: player.starts, duration: player.duration))
        }
    }

    private func seek(toX x: Double) {
        guard width > 0 else { return }
        player.seek(to: Playback.time(atFraction: x / width, of: player.duration))
    }
}

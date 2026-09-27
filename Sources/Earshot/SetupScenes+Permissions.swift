import SwiftUI

// MARK: 3. Permissions

/// The microphone and the Mac's sound, each checked into Earshot's ear: the checks are the real
/// ones, and notes fly from the speaker to the ear while the ding plays.
struct PermissionsScene: View {
    let microphoneAllowed: Bool
    let ding: SetupModel.Ding
    @Environment(\.setupAnimates) private var animates
    @State private var notes = 0
    @State private var glow = false

    var body: some View {
        HStack(spacing: 70) {
            tile("Your voice") {
                icon(systemImage: "mic.fill", colour: SetupColor.me)
                    .background { if animates { Rings() } }
                    .overlay(alignment: .topTrailing) { Check(on: microphoneAllowed) }
            }
            tile("Your Mac's sound") {
                icon(systemImage: "speaker.wave.2.fill", colour: SetupColor.first)
            }
            tile("Earshot") {
                icon(systemImage: "ear", colour: SetupColor.ink)
                    .background {
                        Circle()
                            .stroke(
                                SetupColor.done.opacity(glow ? 0 : 0.6), lineWidth: glow ? 22 : 0
                            )
                            .padding(glow ? -11 : 0)
                    }
                    .overlay(alignment: .topTrailing) { Check(on: ding == .heard) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            ZStack {
                FlyingNote(symbol: "♪", trigger: notes)
                FlyingNote(symbol: "♫", trigger: notes, delay: 0.35)
            }
            .offset(x: 285, y: 100)
        }
        .onChange(of: ding) {
            guard ding == .heard, animates else { return }
            glow = false
            withAnimation(.easeOut(duration: 0.8)) { glow = true }
        }
        .task(id: animates) {
            guard animates else { return }
            try? await play()
        }
    }

    /// The design's loop: the sound travels to the ear every few seconds.
    private func play() async throws {
        while true {
            try await beat(2300)
            notes += 1
            try await beat(4100)
        }
    }

    private func tile(_ name: LocalizedStringKey, @ViewBuilder icon: () -> some View) -> some View {
        VStack(spacing: 10) {
            icon()
            Text(name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SetupColor.ink)
        }
        .frame(width: 130, height: 150)
        .setupCard()
    }

    private func icon(systemImage: String, colour: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(colour)
            .frame(width: 64, height: 64)
            .background(SetupColor.soft, in: .circle)
    }

    /// A green check that springs in.
    private struct Check: View {
        let on: Bool

        var body: some View {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(SetupColor.doneBadge, in: .circle)
                .reveal(on, scale: 0.001)
                .offset(x: 4, y: -4)
        }
    }

    /// Two rings that spread from the microphone, half a cycle apart.
    private struct Rings: View {
        /// The design's ring cycle.
        private static let period = 1.8

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ring(time)
                    ring(time + Self.period / 2)
                }
            }
        }

        private func ring(_ time: Double) -> some View {
            let linear = time.truncatingRemainder(dividingBy: Self.period) / Self.period
            let progress = 1 - pow(1 - linear, 2)
            return Circle()
                .stroke(SetupColor.me, lineWidth: 2)
                .scaleEffect(1 + 0.8 * progress)
                .opacity(0.8 * (1 - progress))
        }
    }

    /// A note arcing from the speaker's tile to the ear.
    private struct FlyingNote: View {
        let symbol: String
        let trigger: Int
        var delay = 0.0

        var body: some View {
            Text(verbatim: symbol)
                .font(.system(size: 22))
                .foregroundStyle(SetupColor.ink)
                .keyframeAnimator(initialValue: NoteArc(), trigger: trigger) { note, arc in
                    note
                        .rotationEffect(.degrees(arc.angle))
                        .offset(x: arc.x, y: arc.y)
                        .opacity(arc.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        LinearKeyframe(0, duration: delay)
                        CubicKeyframe(116, duration: 0.7)
                        CubicKeyframe(193, duration: 0.7)
                    }
                    KeyframeTrack(\.y) {
                        LinearKeyframe(0, duration: delay)
                        CubicKeyframe(-60, duration: 0.7)
                        CubicKeyframe(0, duration: 0.7)
                    }
                    KeyframeTrack(\.angle) {
                        LinearKeyframe(0, duration: delay)
                        CubicKeyframe(-12, duration: 0.7)
                        CubicKeyframe(8, duration: 0.7)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: delay)
                        LinearKeyframe(1, duration: 0.21)
                        LinearKeyframe(1, duration: 0.9)
                        LinearKeyframe(0, duration: 0.29)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Where a flying note is along its arc.
private struct NoteArc {
    var x = 0.0
    var y = 0.0
    var angle = 0.0
    var opacity = 0.0
}

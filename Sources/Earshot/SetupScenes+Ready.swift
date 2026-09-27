import SwiftUI

// MARK: 8. Ready

/// Where Earshot lives: the ear in the menu bar, and a Start Listening button that pops up once
/// with confetti and stays. The menu bar is a drawing; nothing can point at the real ear.
struct ReadyScene: View {
    let title: LocalizedStringKey
    let systemImage: String
    let enabled: Bool
    /// Why the button is off, or how far the models are.
    let status: Text?
    let action: @MainActor () -> Void
    @Environment(\.setupAnimates) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beatShown = 3
    @State private var burst = 0
    @State private var entered = false

    var body: some View {
        VStack(spacing: 12) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(SetupColor.record, in: .capsule)
                    .opacity(enabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .background { Confetti(burst: burst) }
            .scaleEffect(beatShown >= 3 ? 1 : 0.001)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .setupSpring(0.7),
                value: beatShown >= 3)
            status?
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SetupColor.mute)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { menuBar }
        .task(id: animates) {
            guard animates, !entered else {
                beatShown = 3
                return
            }
            entered = true
            try? await enter()
            beatShown = 3
        }
    }

    /// The design's entrance, once: the ear, the pointer, then the button with its confetti.
    private func enter() async throws {
        beatShown = 0
        try await beat(400)
        beatShown = 1
        try await beat(500)
        beatShown = 2
        try await beat(900)
        beatShown = 3
        try await beat(350)
        burst += 1
    }

    private var menuBar: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 14) {
                Text(verbatim: "Wi-Fi")
                ear
                Text(Date.now, format: .dateTime.weekday().hour().minute())
            }
            .font(.system(size: 12))
            .foregroundStyle(SetupColor.mute)
            .padding(.horizontal, 12)
            .frame(width: 580 * 0.84, height: 30, alignment: .trailing)
            .background(SetupColor.card, in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
            Label("Earshot lives here", systemImage: "arrow.up")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SetupColor.ink)
                .opacity(beatShown >= 2 ? 1 : 0)
                .offset(y: beatShown >= 2 ? 0 : 8)
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.2) : .setupSpring(0.5),
                    value: beatShown >= 2
                )
                .padding(.trailing, 20)
        }
        .padding(.top, 10)
        .accessibilityHidden(true)
    }

    private var ear: some View {
        let highlighted = beatShown >= 1
        return Image(nsImage: MenuBarLabel.glyph(recording: false, attention: false))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(highlighted ? SetupColor.ground : SetupColor.ink)
            .frame(width: 22, height: 22)
            .background(highlighted ? SetupColor.ink : .clear, in: .rect(cornerRadius: 6))
            .modifier(Bounce(active: highlighted && animates))
    }
}

/// The design's ear hops in the menu bar, up and back every second, while it is pointed at.
private struct Bounce: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
            let lift = active ? abs(sin(.pi * context.date.timeIntervalSinceReferenceDate)) : 0
            content
                .offset(y: -3 * lift)
                .scaleEffect(1 + 0.08 * lift)
        }
    }
}

/// Paper confetti from the middle of what it covers, once per `burst`, drawn in one canvas that
/// stops redrawing when it lands.
struct Confetti: View {
    let burst: Int
    @State private var pieces: [Piece] = []
    @State private var started: Date?

    /// The design's flight.
    private static let duration = 1.4
    private static let colours = [
        SetupColor.first, SetupColor.second, SetupColor.third, SetupColor.me, SetupColor.record,
        SetupColor.sun,
    ]

    private struct Piece {
        let colour: Color
        let distance: CGSize
        let turn: Double
    }

    var body: some View {
        TimelineView(.animation(paused: started == nil)) { context in
            Canvas { canvas, size in
                guard let started else { return }
                let time = context.date.timeIntervalSince(started) / Self.duration
                guard time < 1 else { return }
                let travelled = 1 - pow(1 - time, 3)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                for piece in pieces {
                    var paper = canvas
                    paper.opacity = 1 - time
                    paper.translateBy(
                        x: centre.x + piece.distance.width * travelled,
                        y: centre.y + piece.distance.height * travelled)
                    paper.rotate(by: .degrees(piece.turn * travelled))
                    paper.fill(
                        Path(
                            roundedRect: CGRect(x: -4, y: -6, width: 8, height: 12), cornerRadius: 2
                        ),
                        with: .color(piece.colour))
                }
            }
        }
        .frame(width: 420, height: 300)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: burst) {
            pieces = (0..<26).map { index in
                let angle = Double.random(in: 0..<(2 * .pi))
                let distance = Double.random(in: 90..<180)
                return Piece(
                    colour: Self.colours[index % Self.colours.count],
                    distance: CGSize(
                        width: cos(angle) * distance, height: sin(angle) * distance * 0.7),
                    turn: .random(in: 0..<540))
            }
            started = .now
        }
        .task(id: started) {
            guard started != nil else { return }
            try? await Task.sleep(for: .seconds(Self.duration))
            started = nil
        }
    }
}

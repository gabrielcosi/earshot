import SwiftUI

/// The pauses between a scene's beats. Throws when the scene goes away, which ends its loop.
func beat(_ milliseconds: Int) async throws {
    try await Task.sleep(for: .milliseconds(milliseconds))
}

// MARK: 1. Welcome

/// A call's voices float into a page as numbered lines.
struct WelcomeScene: View {
    @Environment(\.setupAnimates) private var animates
    @State private var shown = 0
    @State private var talking: Int?
    @State private var flight = 0

    private static let lines: [(speaker: Int, text: LocalizedStringKey)] = [
        (1, "Okay, let's start with the trip."),
        (2, "I found cheap flights for June!"),
        (1, "No way, send me the link."),
        (2, "Sending it right now."),
    ]
    /// The layout is fixed, so where a voice starts and lands is too: the call's tiles and the
    /// page's lines, in the stage's coordinates.
    private static let voices: [Int: CGPoint] = [
        1: CGPoint(x: 88, y: 85), 2: CGPoint(x: 157, y: 85),
    ]
    private static let pageOrigin = CGPoint(x: 316, y: 40)

    var body: some View {
        // The design spreads its pieces across the stage, each centred in an equal share of what
        // is left over.
        HStack(spacing: 122) {
            callBox
            page
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { bubble }
        .task(id: animates) {
            guard animates else {
                (shown, talking) = (Self.lines.count, nil)
                return
            }
            try? await play()
        }
    }

    private func play() async throws {
        while true {
            shown = 0
            for (index, line) in Self.lines.enumerated() {
                talking = line.speaker
                flight = index + 1
                try await beat(900)
                withAnimation(.setupSpring(0.5)) { shown = index + 1 }
                talking = nil
                try await beat(700)
            }
            try await beat(2200)
        }
    }

    private var callBox: some View {
        let colours = SetupColor.speakers
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                person(colours[0], talking: talking == 1)
                person(colours[1], talking: talking == 2)
            }
            GridRow {
                person(colours[2], talking: false)
                person(colours[3], talking: false)
            }
        }
        .padding(10)
        .frame(width: 150, height: 160)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x2E2A38), Color(hex: 0x191820)], startPoint: .topLeading,
                endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20))
    }

    private func person(_ colour: Color, talking: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.white.opacity(0.08))
            .overlay {
                Circle()
                    .fill(colour)
                    .frame(width: 34, height: 34)
                    .phaseAnimator([false, true], trigger: talking) { face, loud in
                        face
                            .scaleEffect(talking && loud ? 1.12 : 1)
                            .background {
                                Circle()
                                    .fill(.white.opacity(talking && loud ? 0.12 : 0))
                                    .padding(-6)
                            }
                    } animation: { _ in
                        talking ? .easeInOut(duration: 0.5) : nil
                    }
            }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.lines.prefix(shown).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    SpeakerBadge(number: line.speaker)
                    Text(line.text)
                        .font(.system(size: 13))
                        .foregroundStyle(SetupColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(16)
        .frame(width: 220, height: 190, alignment: .topLeading)
        .setupCard()
    }

    /// The voice of the line being said, from its speaker's tile to where its line goes.
    @ViewBuilder private var bubble: some View {
        if flight > 0 {
            let line = Self.lines[flight - 1]
            let start = Self.voices[line.speaker] ?? .zero
            let end = CGPoint(
                x: Self.pageOrigin.x + 43, y: Self.pageOrigin.y + 20 + 44 * CGFloat(flight - 1))
            UnevenRoundedRectangle(
                topLeadingRadius: 10, bottomLeadingRadius: 3, bottomTrailingRadius: 10,
                topTrailingRadius: 10
            )
            .fill(SetupColor.speakers[line.speaker - 1])
            .frame(width: 26, height: 20)
            .keyframeAnimator(initialValue: Flight(), trigger: flight) { view, flight in
                view
                    .scaleEffect(flight.scale)
                    .opacity(flight.opacity)
                    .offset(x: flight.x, y: flight.y)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(10, duration: 0.16)
                    CubicKeyframe(end.x - start.x, duration: 0.94)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(-24, duration: 0.16)
                    CubicKeyframe(end.y - start.y, duration: 0.94)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1, duration: 0.16)
                    CubicKeyframe(0.5, duration: 0.94)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.16)
                    LinearKeyframe(0, duration: 0.94)
                }
            }
            .offset(x: start.x - 13, y: start.y - 10)
            .allowsHitTesting(false)
        }
    }

    private struct Flight {
        var x = 0.0
        var y = 0.0
        var scale = 0.4
        var opacity = 0.0
    }
}

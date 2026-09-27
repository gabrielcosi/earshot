import SwiftUI

// MARK: 4. Headphones or speakers

/// A listener in headphones, or a laptop's speakers whose echo an eraser wipes away. It shows the
/// choice below it, and never makes it.
struct ListeningScene: View {
    let speakers: Bool
    @Environment(\.setupAnimates) private var animates
    @State private var echo = true
    @State private var removed = false
    @State private var sweep = 0

    var body: some View {
        HStack(spacing: 160) {
            ZStack {
                Canvas { context, _ in Self.drawFace(in: &context) }
                Canvas { context, _ in Self.drawHeadphones(in: &context) }
                    .opacity(speakers ? 0 : 1)
            }
            .frame(width: 120, height: 150)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in Self.drawLaptop(in: &context) }
                Canvas { context, _ in Self.drawEcho(in: &context) }
                    .opacity(speakers && echo ? 1 : 0)
                Text(verbatim: "✨")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .setupCard(cornerRadius: 12)
                    .keyframeAnimator(initialValue: Wipe(), trigger: sweep) { eraser, wipe in
                        eraser
                            .rotationEffect(.degrees(wipe.angle))
                            .offset(x: 40 + wipe.x, y: 14 + wipe.y)
                            .opacity(wipe.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.x) {
                            LinearKeyframe(-30, duration: 0.001)
                            CubicKeyframe(90, duration: 1.4)
                        }
                        KeyframeTrack(\.y) {
                            LinearKeyframe(0, duration: 0.001)
                            CubicKeyframe(20, duration: 1.4)
                        }
                        KeyframeTrack(\.angle) {
                            LinearKeyframe(-12, duration: 0.001)
                            CubicKeyframe(10, duration: 1.4)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: 0.001)
                            LinearKeyframe(1, duration: 0.28)
                            LinearKeyframe(0, duration: 1.12)
                        }
                    }
                Text("Echo removed")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SetupColor.doneBadge, in: .capsule)
                    .fixedSize()
                    .frame(width: 170)
                    .offset(y: 104)
                    .reveal(removed, offset: CGSize(width: 0, height: 10))
            }
            .frame(width: 170, height: 120)
        }
        .animation(.easeInOut(duration: 0.4), value: speakers)
        .animation(.easeInOut(duration: 0.4), value: echo)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: animates && speakers) {
            (echo, removed) = (true, false)
            guard speakers else { return }
            guard animates else {
                (echo, removed) = (false, true)
                return
            }
            try? await play()
        }
    }

    private func play() async throws {
        while true {
            try await beat(900)
            sweep += 1
            try await beat(700)
            (echo, removed) = (false, true)
            try await beat(1800)
            (echo, removed) = (true, false)
        }
    }

    private struct Wipe {
        var x = 0.0
        var y = 0.0
        var angle = 0.0
        var opacity = 0.0
    }

    private static let skin = Color(hex: 0xF3C9A8)
    private static let features = Color(hex: 0x3A2A22)

    private static func drawFace(in context: inout GraphicsContext) {
        context.fill(
            Path(ellipseIn: CGRect(x: 26, y: 36, width: 68, height: 68)), with: .color(skin))
        context.fill(
            Path(ellipseIn: CGRect(x: 44.5, y: 62.5, width: 7, height: 7)),
            with: .color(features))
        context.fill(
            Path(ellipseIn: CGRect(x: 68.5, y: 62.5, width: 7, height: 7)),
            with: .color(features))
        var smile = Path()
        smile.move(to: CGPoint(x: 50, y: 84))
        smile.addQuadCurve(to: CGPoint(x: 70, y: 84), control: CGPoint(x: 60, y: 92))
        context.stroke(
            smile, with: .color(features), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        context.fill(
            Path(roundedRect: CGRect(x: 53, y: 114, width: 14, height: 22), cornerRadius: 7),
            with: .color(SetupColor.me))
    }

    private static func drawHeadphones(in context: inout GraphicsContext) {
        var band = Path()
        band.addArc(
            center: CGPoint(x: 60, y: 70), radius: 36, startAngle: .degrees(180),
            endAngle: .degrees(0), clockwise: false)
        context.stroke(band, with: .color(SetupColor.ink), lineWidth: 6)
        for x in [16.0, 90] {
            context.fill(
                Path(roundedRect: CGRect(x: x, y: 62, width: 14, height: 26), cornerRadius: 6),
                with: .color(SetupColor.second))
        }
    }

    private static func drawLaptop(in context: inout GraphicsContext) {
        context.fill(
            Path(roundedRect: CGRect(x: 20, y: 10, width: 130, height: 80), cornerRadius: 10),
            with: .color(Color(hex: 0x2B2A33)))
        context.fill(
            Path(roundedRect: CGRect(x: 8, y: 92, width: 154, height: 10), cornerRadius: 5),
            with: .color(SetupColor.line))
        context.fill(
            Path(ellipseIn: CGRect(x: 48, y: 36, width: 28, height: 28)),
            with: .color(SetupColor.first))
        context.fill(
            Path(ellipseIn: CGRect(x: 94, y: 36, width: 28, height: 28)),
            with: .color(SetupColor.third))
    }

    private static func drawEcho(in context: inout GraphicsContext) {
        var waves = Path()
        waves.move(to: CGPoint(x: 150, y: 40))
        waves.addQuadCurve(to: CGPoint(x: 150, y: 60), control: CGPoint(x: 160, y: 50))
        waves.move(to: CGPoint(x: 156, y: 32))
        waves.addQuadCurve(to: CGPoint(x: 156, y: 68), control: CGPoint(x: 174, y: 50))
        context.stroke(
            waves, with: .color(SetupColor.first),
            style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

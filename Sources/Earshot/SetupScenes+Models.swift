import SwiftUI

// MARK: 2. Models

/// The ear fills up as the models download. A progress view, so VoiceOver reads how far it is.
struct EarProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        FillingEar(fraction: configuration.fractionCompleted ?? 0)
    }

    private struct FillingEar: View {
        let fraction: Double
        @Environment(\.setupAnimates) private var animates

        /// The design's wave travels ten crests every 2.4 s.
        private static let crestsPerSecond = 10 / 2.4

        var body: some View {
            TimelineView(.animation(paused: !animates || fraction <= 0 || fraction >= 1)) {
                context in
                let phase = context.date.timeIntervalSinceReferenceDate * Self.crestsPerSecond
                ZStack {
                    EarBulb().fill(SetupColor.soft)
                    Wave(phase: phase.truncatingRemainder(dividingBy: 1), level: fraction)
                        .fill(SetupColor.second)
                        .clipShape(EarBulb())
                    EarOutline()
                        .stroke(
                            SetupColor.ink.opacity(0.25),
                            style: StrokeStyle(lineWidth: 5.6, lineCap: .round))
                }
            }
            .animation(.linear(duration: 0.25), value: fraction)
            .frame(width: 150, height: 150)
        }
    }

    /// Quadratic crests every 12 units of the ear's 24, rising with `level`.
    nonisolated private struct Wave: Shape {
        var phase: Double
        var level: Double

        var animatableData: Double {
            get { level }
            set { level = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let unit = rect.width / 24
            let surface = (24 - level * 25) * unit
            let shift = -phase * 12 * unit
            var path = Path()
            path.move(to: CGPoint(x: shift, y: surface))
            var x = shift
            var up = true
            while x < rect.width {
                path.addQuadCurve(
                    to: CGPoint(x: x + 6 * unit, y: surface),
                    control: CGPoint(x: x + 3 * unit, y: surface + (up ? -1.5 : 1.5) * unit))
                x += 6 * unit
                up.toggle()
            }
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: shift, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// The design's ear, as a solid shape on a 24-unit grid. Its arcs are quarter circles, drawn as
/// the usual cubic approximation.
nonisolated struct EarBulb: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 24
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(12, 1.5))
        path.addCurve(to: point(3.5, 10), control1: point(7.305, 1.5), control2: point(3.5, 5.305))
        path.addCurve(to: point(6.4, 16), control1: point(3.5, 13.2), control2: point(5.2, 14.6))
        path.addCurve(to: point(7.7, 19.8), control1: point(7.4, 17.2), control2: point(7.7, 18.3))
        path.addCurve(
            to: point(11.6, 23.5), control1: point(7.7, 22.1), control2: point(9.5, 23.5))
        path.addCurve(
            to: point(15.4, 20.1), control1: point(13.7, 23.5), control2: point(15.4, 22))
        path.addCurve(
            to: point(17.4, 16.8), control1: point(15.4, 18.6), control2: point(16.4, 17.8))
        path.addCurve(
            to: point(20.5, 10), control1: point(18.8, 15.4), control2: point(20.5, 13.6))
        path.addCurve(
            to: point(12, 1.5), control1: point(20.5, 5.305), control2: point(16.695, 1.5))
        path.closeSubpath()
        return path
    }
}

/// The design's ear as two strokes: its rim and its inner curl.
nonisolated struct EarOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 24
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(12, 3))
        path.addCurve(to: point(5, 10), control1: point(8.134, 3), control2: point(5, 6.134))
        path.addCurve(to: point(7.5, 15), control1: point(5, 12.6), control2: point(6.5, 13.8))
        path.addCurve(to: point(8.6, 18.3), control1: point(8.4, 16.1), control2: point(8.6, 17.1))
        path.addCurve(
            to: point(11.8, 21.3), control1: point(8.6, 20.2), control2: point(10.1, 21.3))
        path.addCurve(
            to: point(14.9, 18.6), control1: point(13.5, 21.3), control2: point(14.9, 20.1))
        path.move(to: point(9.5, 10))
        path.addCurve(to: point(12, 7.5), control1: point(9.5, 8.619), control2: point(10.619, 7.5))
        path.addCurve(
            to: point(14.5, 10), control1: point(13.381, 7.5), control2: point(14.5, 8.619))
        path.addCurve(to: point(13.1, 13.4), control1: point(14.5, 11.5), control2: point(13.1, 12))
        return path
    }
}

struct ModelsScene: View {
    let download: SetupModel.Download
    @Environment(\.setupAnimates) private var animates
    @State private var burst = 0

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: fraction) {
                Text("Speech models")
            }
            .progressViewStyle(EarProgressStyle())
            .accessibilityValue(caption)
            .overlay { Sparks(burst: burst) }
            Text(caption)
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(SetupColor.ink)
                .contentTransition(.numericText(value: fraction))
                .animation(.default, value: fraction)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: download) { old, new in
            if new == .done, old != .done, animates { burst += 1 }
        }
    }

    private var fraction: Double {
        switch download {
        case .downloading(let fraction): fraction
        case .verifying, .done: 1
        default: 0
        }
    }

    private var caption: String {
        switch download {
        case .done: String(localized: "Ready!")
        case .verifying: String(localized: "Almost ready…")
        default: fraction.formatted(.percent.precision(.fractionLength(0)))
        }
    }
}

/// Fourteen sparks fly out of the ear when it is full.
private struct Sparks: View {
    let burst: Int

    var body: some View {
        let colours = SetupColor.speakers
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                let angle = Double(index) / 14 * 2 * .pi
                Circle()
                    .fill(colours[index % colours.count])
                    .frame(width: 8, height: 8)
                    .keyframeAnimator(initialValue: 0.0, trigger: burst) { spark, progress in
                        spark
                            .scaleEffect(1 - 0.8 * progress)
                            .opacity(progress > 0 && progress < 1 ? 1 - progress : 0)
                            .offset(x: cos(angle) * 110 * progress, y: sin(angle) * 90 * progress)
                    } keyframes: { _ in
                        LinearKeyframe(0.001, duration: 0.001)
                        CubicKeyframe(1, duration: 0.9)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

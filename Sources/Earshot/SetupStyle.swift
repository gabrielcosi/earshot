import AppKit
import EarshotKit
import SwiftUI

/// The approved setup design's colours: its own warm neutrals, the speaker colours of its
/// illustrations, and a sky of three colours per step.
enum SetupColor {
    static let ground = Color(light: 0xF6F1EE, dark: 0x101014)
    static let ink = Color(light: 0x17161A, dark: 0xF4F2F5)
    static let mute = Color(
        light: 0x6E6A72, dark: 0xA09CA6, lightContrast: 0x46424A, darkContrast: 0xCFCBD4)
    static let glass = Color(light: 0xFFFFFF, lightAlpha: 0.55, dark: 0x1C1B21, darkAlpha: 0.62)
    static let card = Color(light: 0xFFFFFF, dark: 0x26252C)
    static let soft = Color(light: 0xF1EDF0, dark: 0x2F2D35)
    static let line = Color(light: 0xE4DEE2, dark: 0x3A3841)
    static let me = Color(hex: 0x4E8BFF)
    static let first = Color(hex: 0xFF7A45)
    static let second = Color(hex: 0x9B6BFF)
    static let third = Color(hex: 0x1FAE8C)
    static let record = Color(hex: 0xFF3B30)
    static let done = Color(hex: 0x28C167)
    /// The design's green, darkened until white text on it reads at 4.5:1.
    static let doneBadge = Color(hex: 0x19803F)
    static let sun = Color(hex: 0xFFD580)
    /// The illustrations' speakers 1 to 4, as on their call tiles and badges.
    static let speakers = [first, second, third, me]

    static func sky(_ step: SetupStep) -> [Color] {
        let hexes: [UInt32] =
            switch step {
            case .welcome: [0xFFB38A, 0xFF8FB1, 0xFFD580]
            case .models: [0xB9A7FF, 0x8FD3FF, 0xFFC6E5]
            case .permissions: [0x9EF0CF, 0xFFE38A, 0xA8D8FF]
            case .listening: [0x8FD3FF, 0xC3B1FF, 0x9EF0CF]
            case .languages: [0xFF9E8A, 0xFFD580, 0xFF8FB1]
            case .transcripts: [0x9EF0CF, 0x8FD3FF, 0xFFE38A]
            case .captions: [0xC3B1FF, 0xFF8FB1, 0x8FD3FF]
            case .ready: [0xFFB38A, 0xB9A7FF, 0x9EF0CF]
            }
        return hexes.map { Color(hex: $0) }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    /// The contrast colours are for Increase Contrast; without them it keeps the others.
    init(
        light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1,
        lightContrast: UInt32? = nil, darkContrast: UInt32? = nil
    ) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua,
                    .accessibilityHighContrastDarkAqua,
                ]) {
                case .darkAqua: NSColor(hex: dark, alpha: darkAlpha)
                case .accessibilityHighContrastDarkAqua:
                    NSColor(hex: darkContrast ?? dark, alpha: darkAlpha)
                case .accessibilityHighContrastAqua:
                    NSColor(hex: lightContrast ?? light, alpha: lightAlpha)
                default: NSColor(hex: light, alpha: lightAlpha)
                }
            })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32, alpha: Double) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension EnvironmentValues {
    /// Scenes loop only while this is on: off with Reduce Motion, and while the window is not
    /// frontmost, where nobody watches and the loops would only cost battery.
    @Entry var setupAnimates = true
}

/// The approved design's springs: CSS `cubic-bezier(.3, 1.45, .5, 1)` overshoots by about 10 %,
/// which a spring at this damping matches.
extension Animation {
    static func setupSpring(_ duration: Double = 0.55) -> Animation {
        .spring(duration: duration, bounce: 0.35)
    }
}

/// The window's ground: the step's three colours as a soft mesh under the design's frosted glass,
/// shifting colour when the step changes and drifting slowly while `animates`.
struct SetupBackground: View {
    let step: SetupStep
    let animates: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// The design's blobs drift over 18, 22, and 26 s, back and forth.
    private static let periods: [Double] = [36, 44, 52]
    /// The drift moves a few points a second; more frames would not show.
    private static let frameInterval = 1.0 / 30

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !animates)) {
            context in
            MeshGradient(
                width: 3, height: 3, points: Self.points(at: context.date), colors: colors)
        }
        .opacity(colorScheme == .dark ? 0.32 : 0.75)
        .background(SetupColor.ground)
        .overlay(SetupColor.glass)
        .animation(.easeInOut(duration: 1.2), value: step)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let sky = SetupColor.sky(step)
        let ground = SetupColor.ground
        return [
            sky[0], ground, sky[1],
            sky[0], ground, sky[1],
            ground, sky[2], ground,
        ]
    }

    private static func points(at date: Date) -> [SIMD2<Float>] {
        let time = date.timeIntervalSinceReferenceDate
        let wave = periods.map { Float(sin(2 * .pi * time / $0)) }
        return [
            [0, 0], [0.5 + 0.12 * wave[0], 0], [1, 0],
            [0, 0.5 + 0.1 * wave[1]], [0.5 + 0.1 * wave[1], 0.5 + 0.1 * wave[2]],
            [1, 0.5 - 0.1 * wave[0]],
            [0, 1], [0.5 - 0.12 * wave[2], 1], [1, 1],
        ]
    }
}

/// The design's pill-shaped segmented control, agreed as a custom piece: a thumb that springs to
/// the choice. VoiceOver reads it as a native segmented picker; with Full Keyboard Access, each
/// choice is a button.
struct PillPicker<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, name: String)]
    @Binding var selection: Value
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let chosen = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(chosen ? SetupColor.ink : SetupColor.mute)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background {
                            if chosen {
                                Capsule()
                                    .fill(SetupColor.card)
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(SetupColor.soft, in: .capsule)
        .overlay {
            if contrast == .increased { Capsule().strokeBorder(SetupColor.mute) }
        }
        .opacity(isEnabled ? 1 : 0.35)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .setupSpring(), value: selection)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { Text($0.name).tag($0.value) }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// The design's switch, agreed as a custom piece: green when on, its knob springing across.
/// VoiceOver reads it as a native switch.
struct PillSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillSwitch(configuration: configuration)
    }

    private struct PillSwitch: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(configuration.isOn ? SetupColor.done : SetupColor.line)
                        .frame(width: 54, height: 32)
                        .overlay {
                            if contrast == .increased, !configuration.isOn {
                                Capsule().strokeBorder(SetupColor.mute)
                            }
                        }
                        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                            Circle()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                                .frame(width: 26, height: 26)
                                .padding(3)
                        }
                    configuration.label
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SetupColor.ink)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .setupSpring(0.5),
                value: configuration.isOn
            )
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }
}

/// Where setup is, as the design's dots: decorative, since VoiceOver hears "Step 3 of 8" with
/// each page's heading.
struct PageDots: View {
    let position: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            ForEach(1...SetupFlow.count, id: \.self) { dot in
                Capsule()
                    .fill(dot == position ? SetupColor.ink : SetupColor.line)
                    .frame(width: dot == position ? 26 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .setupSpring(0.5), value: position)
        .accessibilityHidden(true)
    }
}

/// A speaker's numbered badge, as the transcript illustrations show them.
struct SpeakerBadge: View {
    let number: Int

    var body: some View {
        let colour = SetupColor.speakers[(number - 1) % SetupColor.speakers.count]
        Text(number, format: .number)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(colour, in: .rect(cornerRadius: 7))
    }
}

extension View {
    /// The design's white cards, with their soft shadow.
    func setupCard(cornerRadius: CGFloat = 18) -> some View {
        background(SetupColor.card, in: .rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.25), radius: 15, y: 10)
    }
}

/// Shows or hides something with the design's spring and movement from `hidden`; under Reduce
/// Motion it only fades, and nothing moves.
private struct Reveal: ViewModifier {
    let shown: Bool
    let scale: Double
    let angle: Double
    let offset: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = shown || reduceMotion
        content
            .scaleEffect(still ? 1 : scale)
            .rotationEffect(.degrees(still ? 0 : angle))
            .offset(still ? .zero : offset)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? .easeInOut(duration: 0.25) : .setupSpring(0.6), value: shown)
    }
}

extension View {
    func reveal(_ shown: Bool, scale: Double = 1, angle: Double = 0, offset: CGSize = .zero)
        -> some View
    {
        modifier(Reveal(shown: shown, scale: scale, angle: angle, offset: offset))
    }
}

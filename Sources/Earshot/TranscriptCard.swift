import AppKit
import EarshotKit
import SwiftUI

/// One line: who and when in a column on the left, the text on the right after a rule in the
/// speaker's colour, and the translation under it.
struct TranscriptCard: View {
    struct Playback {
        let playing: Bool
        let toggle: () -> Void
    }

    let line: TranscriptLine
    let display: TranslationDisplay
    let textSize: Double
    let playback: Playback?

    var body: some View {
        let text = display.text(original: line.text, translation: line.translation)
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                SpeakerName(name: line.speaker, badge: line.badge, colour: line.voice.colour)
                HStack(spacing: 4) {
                    Text(MarkdownExport.timestamp(line.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let playback {
                        Button(
                            playback.playing ? "Stop" : "Play",
                            systemImage: playback.playing ? "stop.fill" : "play.fill",
                            action: playback.toggle
                        )
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .padding(.leading, SpeakerName.indent)
            }
            .frame(width: SpeakerName.columnWidth, alignment: .leading)
            LineText(main: text.main, under: text.under, textSize: textSize)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(nsColor: line.voice.colour)).frame(width: 2)
                }
                .textSelection(.enabled)
        }
        .padding(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                "\(line.speaker), \(Self.spoken(line.start))", text.main,
                text.under.map { "Translation: \($0)" },
            ].compactMap(\.self).joined(separator: ". ")
        )
        .accessibilityActions {
            if let playback {
                Button(playback.playing ? "Stop" : "Play", action: playback.toggle)
            }
        }
    }

    /// "1 minute, 5 seconds" rather than "01:05", which VoiceOver reads as a clock time.
    private static func spoken(_ seconds: Double) -> String {
        Duration.seconds(Int(seconds)).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

/// The words still being recognized on each channel that is speaking, pinned under the transcript
/// until their final arrives and they become a card.
struct LiveBars: View {
    let display: TranslationDisplay
    let textSize: Double
    @Environment(SessionController.self) private var controller

    var body: some View {
        if controller.engineLoading || !controller.transcript.liveLines.isEmpty {
            bars
        }
    }

    private var bars: some View {
        VStack(spacing: 6) {
            if controller.engineLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading models, the transcript will catch up")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(.bar, in: .rect(cornerRadius: 10))
            }
            ForEach(controller.transcript.liveLines) { live in
                bar(live)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func bar(_ live: LiveLine) -> some View {
        let text = display.text(
            original: controller.rules.apply(live.text), translation: live.translation)
        let me = live.channel == .microphone
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                SpeakerName(
                    name: me ? "Me" : "Live", badge: me ? "M" : "…",
                    colour: (me ? TranscriptLine.Voice.me : .unknown).colour)
                Text("now").font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, SpeakerName.indent)
            }
            .frame(width: SpeakerName.columnWidth, alignment: .leading)
            LineText(main: text.main, under: text.under, textSize: textSize, pending: true)
                .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 2) }
        }
        .padding(12)
        .background(.bar, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct SpeakerName: View {
    let name: String
    let badge: String
    let colour: NSColor

    /// The mockup's left column, wide enough for "Speaker 10" beside its badge.
    static let columnWidth = 128.0
    static let badgeSide = 18.0
    static let spacing = 7.0
    /// Lines the time up with the name, past the badge.
    static let indent = badgeSide + spacing

    var body: some View {
        HStack(spacing: Self.spacing) {
            Text(badge)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(nsColor: .label(on: colour)))
                .frame(width: Self.badgeSide, height: Self.badgeSide)
                .background(Color(nsColor: colour), in: .rect(cornerRadius: 5))
                .accessibilityHidden(true)
            Text(name).font(.callout.weight(.semibold)).lineLimit(1)
        }
    }
}

private struct LineText: View {
    let main: String
    let under: String?
    let textSize: Double
    var pending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(main)
                .font(.system(size: textSize))
                .foregroundStyle(pending ? .secondary : .primary)
            if let under {
                Text(under)
                    .font(.system(size: textSize * 0.9))
                    .foregroundStyle(Color.translation)
            }
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TranscriptLine.Voice {
    /// System colours, which follow light, dark, and Increase Contrast. Red is left out: it means
    /// recording and errors here.
    var colour: NSColor {
        switch self {
        case .me: .systemBlue
        case .unknown: .systemGray
        case .other(let index): Self.palette[index % Self.palette.count]
        }
    }

    private static let palette: [NSColor] = [
        .systemOrange, .systemPurple, .systemGreen, .systemPink, .systemIndigo, .systemBrown,
        .systemTeal,
    ]
}

extension NSColor {
    /// Black or white, whichever contrasts more with `background` as it resolves in the current
    /// appearance. One of the two always reaches at least 4.58:1 (the square root of 21), so no
    /// badge falls under 3:1. The switch is at relative luminance 0.179, where both contrast
    /// equally: (1 + 0.05) / (L + 0.05) = (L + 0.05) / (0 + 0.05).
    static func label(on background: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            var dark = false
            appearance.performAsCurrentDrawingAppearance {
                dark = (background.usingColorSpace(.sRGB)?.relativeLuminance ?? 0) > 0.179
            }
            return dark ? .black : .white
        }
    }

    private var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(redComponent) + 0.7152 * linear(greenComponent) + 0.0722
            * linear(blueComponent)
    }
}

extension Color {
    /// The mockup's teal, darkened until it reads as body text: at least 4.5:1 against the window
    /// in light and dark (WCAG AA), and 7:1 with Increase Contrast (AAA).
    static let translation = Color(
        nsColor: NSColor(name: "translation") { appearance in
            let hex: Int =
                switch appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua,
                    .accessibilityHighContrastDarkAqua,
                ]) {
                case .darkAqua: 0x5CC8C4
                case .accessibilityHighContrastAqua: 0x055457
                case .accessibilityHighContrastDarkAqua: 0x8FE3E0
                default: 0x086A6E
                }
            return NSColor(
                srgbRed: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1)
        })
}

struct SummaryView: View {
    let summary: TranscriptDocument.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "text.badge.star").font(.headline)
            Text(
                (try? AttributedString(
                    markdown: summary.text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(summary.text))
            Text("Written by \(summary.model). Check it against the transcript.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .textSelection(.enabled)
    }
}

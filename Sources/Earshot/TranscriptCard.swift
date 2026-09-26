import AppKit
import EarshotKit
import SwiftUI

/// One line: who and when in a column on the left, the text on the right after a rule in the
/// speaker's colour, and the translation under it.
struct TranscriptCard: View {
    struct Playback {
        /// The line the player is in, highlighted.
        let current: Bool
        let play: () -> Void
    }

    let line: TranscriptLine
    let display: TranslationDisplay
    let textSize: Double
    let playback: Playback?
    /// Wide enough for the transcript's widest label, as the page measures it.
    let columnWidth: Double

    var body: some View {
        let text = display.text(original: line.text, translation: line.translation)
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            SpeakerColumn(line: line, play: playback?.play)
                .frame(width: columnWidth, alignment: .leading)
            LineText(main: text.main, under: text.under, textSize: textSize)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(nsColor: line.voice.colour)).frame(width: 2)
                }
                .textSelection(.enabled)
        }
        .padding(10)
        .background {
            if playback?.current == true {
                RoundedRectangle(cornerRadius: 10).fill(.tint.quinary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                playback?.current == true ? "Playing" : nil,
                "\(line.speaker), \(Self.spoken(line.start))", text.main,
                text.under.map { "Translation: \($0)" },
            ].compactMap(\.self).joined(separator: ". ")
        )
        .accessibilityActions {
            if let playback { Button("Play from Here", action: playback.play) }
        }
    }

    /// "1 minute, 5 seconds" rather than "01:05", which VoiceOver reads as a clock time.
    static func spoken(_ seconds: Double) -> String {
        Duration.seconds(Int(seconds)).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

/// Who said a line and when, with a button to play from there when the audio was kept.
struct SpeakerColumn: View {
    let line: TranscriptLine
    let play: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SpeakerName(name: line.speaker, badge: line.badge, colour: line.voice.colour)
            HStack(spacing: 4) {
                Text(MarkdownExport.timestamp(line.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let play {
                    Button("Play from Here", systemImage: "play.fill", action: play)
                        .labelStyle(.iconOnly)
                        .help("Play from here")
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
            .padding(.leading, SpeakerName.indent)
        }
    }
}

struct SpeakerName: View {
    let name: String
    let badge: String
    let colour: NSColor

    /// The widest the speaker column gets, from the design: "Speaker 10" beside its badge fits,
    /// and a longer name is cut short.
    static let maxColumnWidth = 128.0
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

struct LineText: View {
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
                    .foregroundStyle(pending ? Color.secondary : Color.translation)
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

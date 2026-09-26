import AppKit
import EarshotCapture
import EarshotKit
import SwiftUI

/// The bottom of a live transcript: how long it has been listening, a level meter for each source,
/// and Stop; under them, the words still being recognized on each source, until their final makes
/// them a line above.
struct LiveArea: View {
    let display: TranslationDisplay
    let textSize: Double
    let columnWidth: Double
    @Environment(SessionController.self) private var controller

    /// Said here and in the menu while the engine loads.
    static let loadingMessage = "Loading the speech engine. The transcript will catch up."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                status
                if controller.engineLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(LiveArea.loadingMessage).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                } else if controller.transcript.liveLines.isEmpty {
                    // Before the first line the page says it already.
                    if !controller.transcript.utterances.isEmpty {
                        Text("Listening…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                    }
                } else {
                    ForEach(controller.transcript.liveLines) { live in
                        LiveLineRow(
                            channel: live.channel, live: live, display: display,
                            textSize: textSize, columnWidth: columnWidth
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private var status: some View {
        HStack(spacing: 14) {
            if case .recording(let since) = controller.state {
                HStack(spacing: 8) {
                    RecordingDot()
                    Text("Listening").fontWeight(.semibold)
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(timerInterval: since...Date.distantFuture, countsDown: false)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                            .accessibilityLabel(
                                TranscriptCard.spoken(context.date.timeIntervalSince(since)))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            meters
            Spacer()
            Button("Stop", systemImage: "stop.fill") {
                Task { await controller.stop() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!controller.isRecording)
        }
        .padding(.horizontal, 10)
    }

    private var meters: some View {
        HStack(spacing: 14) {
            ForEach([Channel.microphone, .system], id: \.self) { channel in
                if let meter = controller.levels[channel] {
                    SourceMeter(
                        meter: meter,
                        name: LiveSource(channel: channel, sources: controller.sources).name,
                        colour: Color(nsColor: LiveSource.colour(channel)))
                }
            }
        }
    }
}

/// Words still being recognized on one channel: its source in the speaker column, then the text
/// after a dashed rule, with word rules applied as they will be to the final. Until there are words
/// it may show, the source's level says it is heard: "Translating…" while showing translations
/// alone and the words wait for theirs, "Listening…" before anyone speaks.
struct LiveLineRow: View {
    let channel: Channel
    let live: LiveLine?
    let display: TranslationDisplay
    let textSize: Double
    let columnWidth: Double
    @Environment(SessionController.self) private var controller

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            LiveSourceLabel(channel: channel)
                .frame(width: columnWidth, alignment: .leading)
            words
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var words: some View {
        let original = live.map { controller.rules.apply($0.text) } ?? ""
        if let live,
            display != .translation
                || !controller.awaitsTranslation(live: original, translation: live.translation)
        {
            let text = display.text(original: original, translation: live.translation)
            LineText(
                main: text.main, under: text.under, textSize: textSize,
                colour: LiveSource.colour(channel), pending: true)
        } else {
            HStack(spacing: 8) {
                if let meter = controller.levels[channel] {
                    SourceMeter(
                        meter: meter,
                        name: LiveSource(channel: channel, sources: controller.sources).name,
                        colour: Color(nsColor: LiveSource.colour(channel)), showsName: false)
                }
                Text(live == nil ? "Listening…" : "Translating…")
                    .font(.system(size: textSize))
                    .foregroundStyle(.secondary)
            }
            .lineRule(LiveSource.colour(channel), pending: true)
        }
    }
}

/// The red dot of a recording, pulsing unless Reduce Motion is on.
struct RecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "circle.fill")
            .imageScale(.small)
            .foregroundStyle(.red)
            .symbolEffect(.pulse, isActive: !reduceMotion)
            .accessibilityHidden(true)
    }
}

/// A source's meter and name. The levels are copied out of the meter once a window, into state
/// of this view alone, so only the meter redraws.
private struct SourceMeter: View {
    let meter: LevelMeter
    let name: String
    let colour: Color
    var showsName = true
    @State private var levels: [Double] = []

    var body: some View {
        HStack(spacing: 6) {
            LevelBars(levels: levels, colour: colour)
            if showsName {
                Text(name).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) level")
        .accessibilityValue((levels.last ?? 0).formatted(.percent.precision(.fractionLength(0))))
        .task(id: ObjectIdentifier(meter)) {
            while !Task.isCancelled {
                levels = meter.levels
                try? await Task.sleep(for: LevelMeter.window)
            }
        }
    }
}

/// A source's level over the last second as bars, newest on the right: the design's meter.
private struct LevelBars: View {
    let levels: [Double]
    let colour: Color

    /// The design's meter: 3 pt bars 2 pt apart, as tall as a line of the strip's text.
    private static let barWidth = 3.0
    private static let gap = 2.0
    private static let height = 14.0

    var body: some View {
        Canvas { context, size in
            for (index, level) in levels.enumerated() {
                let barHeight = max(Self.barWidth, level * size.height)
                let rect = CGRect(
                    x: Double(index) * (Self.barWidth + Self.gap),
                    y: (size.height - barHeight) / 2, width: Self.barWidth, height: barHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1), with: .color(colour))
            }
        }
        .frame(
            width: Double(LevelMeter.history) * (Self.barWidth + Self.gap) - Self.gap,
            height: Self.height)
    }
}

/// What a live line's channel is called: the microphone is "Me"; the Mac's audio is named after
/// the apps listened to: one or two by name, more by count as the menu's Listening to counts
/// them, and "All apps" for every app.
struct LiveSource {
    let channel: Channel
    let sources: [AudioSource]

    var name: String {
        guard channel == .system else { return "Me" }
        switch sources.count {
        case 0: return "All apps"
        case 1, 2: return sources.map(\.name).joined(separator: ", ")
        case let count: return "\(count) apps"
        }
    }

    /// The first two apps' icons, nil for one without; a single nil when listening to every app.
    var icons: [NSImage?] {
        sources.isEmpty ? [nil] : sources.prefix(2).map { Self.icon(of: $0) }
    }

    static func colour(_ channel: Channel) -> NSColor {
        (channel == .microphone ? TranscriptLine.Voice.me : .unknown).colour
    }

    /// Looked up once per app: the label is drawn again with every partial.
    private static var icons: [String: NSImage?] = [:]

    /// Nil for a process no app launched, which has no icon of its own.
    private static func icon(of source: AudioSource) -> NSImage? {
        if let icon = icons[source.id] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.id)
            .map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
        icons[source.id] = icon
        return icon
    }
}

/// A live line's source in the speaker column: the "Me" badge, or the apps' icons, at most two,
/// overlapping as the Dock's stacks do; a grey speaker badge for all apps, or an app without one.
struct LiveSourceLabel: View {
    let channel: Channel
    @Environment(SessionController.self) private var controller

    var body: some View {
        let source = LiveSource(channel: channel, sources: controller.sources)
        if channel == .microphone {
            SpeakerName(name: source.name, badge: "M", colour: LiveSource.colour(channel))
        } else {
            HStack(spacing: SpeakerName.spacing) {
                HStack(spacing: -SpeakerName.badgeSide / 3) {
                    ForEach(Array(source.icons.enumerated()), id: \.offset) { _, icon in
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: SpeakerName.badgeSide, height: SpeakerName.badgeSide)
                        } else {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(
                                    Color(nsColor: .label(on: LiveSource.colour(channel)))
                                )
                                .frame(width: SpeakerName.badgeSide, height: SpeakerName.badgeSide)
                                .background(
                                    Color(nsColor: LiveSource.colour(channel)),
                                    in: .rect(cornerRadius: 5))
                        }
                    }
                }
                .accessibilityHidden(true)
                Text(source.name).font(.callout.weight(.semibold)).lineLimit(1)
            }
        }
    }
}

import AppKit
import EarshotKit
import SwiftUI

enum CaptionsSettings {
    static let textSize = "captionsTextSize"
    static let display = "captionsDisplay"
}

/// The captions overlay's content: the last turns and the words still being recognized, from the
/// panel's top edge down, as many as its height holds, or why listening stopped when it stopped on
/// its own. What it listens to and its controls float over the top, where the text fades out.
struct CaptionsOverlay: View {
    @Environment(SessionController.self) private var controller
    @AppStorage(CaptionsSettings.textSize) private var textSize = CaptionTextSize.medium
    /// Its own, starting as the window's.
    @AppStorage(CaptionsSettings.display) private var display =
        UserDefaults.standard.string(forKey: TranscriptSettings.display)
        .flatMap(TranslationDisplay.init) ?? .both
    /// The height of the row that floats over the top.
    @State private var bar = 0.0

    /// Room for the widest speaker column, and as much again for the words.
    private static let minWidth = 2 * SpeakerName.maxColumnWidth + 2 * 14 + 2 * padding
    private static let padding = 10.0

    var body: some View {
        let title = self.title
        let underBar = problems.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            if !underBar {
                topBar(title: title).hidden()
                ForEach(problems) { problem in
                    ProblemRow(problem: problem, dismissible: false)
                }
                .buttonStyle(.glass)
            }
            if !stopped {
                // Dragged from the text; the controls are left out of the drag, so their clicks
                // reach them.
                CaptionLines(
                    display: title == nil ? .original : display, textSize: textSize.points,
                    top: underBar ? bar : 0, legibleTop: (underBar ? bar : 0) + fade
                )
                .mask {
                    // Nothing shows under the status and controls; below them the text fades in.
                    VStack(spacing: 0) {
                        if underBar { topBar(title: title).hidden() }
                        LinearGradient(
                            colors: [.clear, .black], startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: fade)
                        Color.black
                    }
                }
                .gesture(WindowDragGesture())
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.bottom, Self.padding)
        .frame(minWidth: Self.minWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Over bright video the HUD material renders mid-grey: #868686 in the maintainer's
        // recording, where the secondary level was near-invisible. Tinted, it renders #434343:
        // finished lines (#E6E6E6) 7.9:1, live ones (the secondary level, #BCBCBC) 5.2:1,
        // measured.
        .background(.black.opacity(0.55))
        .foregroundStyle(Color.primary, Color.primary.opacity(0.7))
        .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
        .overlay(alignment: .top) {
            topBar(title: title)
                .onGeometryChange(for: Double.self) {
                    $0.size.height
                } action: {
                    bar = $0
                }
        }
        .allowsWindowActivationEvents()
        // The panel never becomes key, so its controls, the problems' buttons among them, would
        // always look inactive, as if disabled.
        .environment(\.controlActiveState, .key)
    }

    /// Half a line: text scrolling up fades out over it rather than being cut.
    private var fade: Double { textSize.points / 2 }

    private var stopped: Bool { controller.state == .idle && controller.endedOnItsOwn }

    /// Why listening stopped; while listening, why lines go untranslated.
    private var problems: [Problem] {
        controller.problems.all.filter { stopped ? $0.endsWithSession : $0.isTranslation }
    }

    /// Nil when nothing is translated.
    private var title: String? {
        CaptionsTitle.text(
            spoken: controller.spokenLanguages, target: controller.primaryLanguage,
            translating: controller.translationEnabled)
    }

    private func topBar(title: String?) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if !stopped {
                    if controller.isRecording {
                        RecordingDot()
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(status(title: title)).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .gesture(WindowDragGesture())
            Spacer(minLength: 6)
            if !stopped, title != nil {
                // A picker sets its choice, where a toggle flips it: a click that arrives twice
                // on the never-key panel still lands on what was chosen.
                Menu {
                    Picker("Show", selection: $display) {
                        ForEach(TranslationDisplay.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label("Show", systemImage: "globe")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .help("Show the original, the translation, or both")
            }
            Button("Hide Captions", systemImage: "xmark") { controller.captionsDismissed = true }
                .help("Hide the captions until you start listening again")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func status(title: String?) -> String {
        if stopped { return "Listening stopped" }
        switch controller.state {
        case .starting: return "Starting…"
        case .stopping: return "Finishing…"
        case .recording, .idle:
            return ["Listening", title].compactMap(\.self).joined(separator: " · ")
        }
    }
}

/// The last turns and the words still being recognized, newest at the bottom, in the height the
/// user gives the overlay. A turn can be minutes of one speaker, so what does not fit scrolls up
/// and out at the top.
private struct CaptionLines: View {
    let display: TranslationDisplay
    let textSize: Double
    /// Room for the row that floats over the top, above the least text the overlay shows.
    let top: Double
    /// Where text is legible again below that row: a speaker's name moves down to it.
    let legibleTop: Double
    @Environment(SessionController.self) private var controller
    /// Rebuilt only when the last turns change, not with every partial.
    @State private var lines: [TranscriptLine] = []
    /// Grows to fit every speaker shown this session and never narrows, so rows do not shift.
    @State private var columnWidth = 0.0
    @State private var height = 0.0

    /// The approved design's gap between rows.
    private static let spacing = 8.0
    nonisolated static let area = "captions"

    /// A turn is at least a line tall, so no more than this many can show; the rest are not laid
    /// out, however long the session.
    private var turns: Int { Int(height / textSize) + 1 }

    var body: some View {
        let live = controller.transcript.liveLines
        // The least it shows: the words being recognized and the line before them.
        VStack(spacing: Self.spacing) {
            Color.clear.frame(height: top)
            LineText(main: " ", under: nil, textSize: textSize, colour: .clear)
            LineText(main: " ", under: nil, textSize: textSize, colour: .clear)
        }
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Double.self) {
            $0.size.height
        } action: {
            height = $0
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(lines) { line in
                    // Showing translations alone, a turn waiting for its translation shows once
                    // it has one.
                    if display != .translation
                        || !controller.awaitsTranslation(line)
                    {
                        CaptionRow(
                            line: line, display: display, textSize: textSize,
                            columnWidth: columnWidth, legibleTop: legibleTop)
                    }
                }
                // Each source keeps its row while listening, so the overlay never looks idle.
                if let status {
                    Text(status).font(.system(size: textSize)).foregroundStyle(.secondary)
                } else {
                    ForEach(Channel.allCases.filter { controller.levels[$0] != nil }, id: \.self) {
                        channel in
                        LiveLineRow(
                            channel: channel, live: live.first { $0.channel == channel },
                            display: display, textSize: textSize, columnWidth: columnWidth)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .coordinateSpace(.named(Self.area))
        .clipped()
        .background {
            SpeakerColumnSizer(lines: lines, channels: Array(controller.levels.keys)) { width in
                columnWidth = max(columnWidth, width)
            }
        }
        .onChange(of: Array(controller.transcript.utterances.suffix(turns)), initial: true) {
            show()
        }
        .onChange(of: controller.names) { show() }
        .onChange(of: controller.rules) { show() }
    }

    private func show() {
        lines = TranscriptLine.latest(
            turns, in: controller.transcript, names: controller.names, rules: controller.rules)
    }

    /// Before the sources' rows: while starting, and while the engine loads.
    private var status: String? {
        if controller.engineLoading { return LiveArea.loadingMessage }
        return controller.state == .starting ? "Starting…" : nil
    }
}

/// A finished turn: its speaker, then its text after a rule in the speaker's colour, as in the
/// window. Once the turn's start has scrolled away, its speaker's name stays in sight beside what
/// is left of it.
private struct CaptionRow: View {
    let line: TranscriptLine
    let display: TranslationDisplay
    let textSize: Double
    let columnWidth: Double
    /// Where legible text starts in the captions area.
    let legibleTop: Double
    /// In the captions area: above its top once scrolled past.
    @State private var frame = CGRect.zero

    var body: some View {
        let text = display.text(original: line.text, translation: line.translation)
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            SpeakerName(name: line.speaker, badge: line.badge, colour: line.voice.colour)
                .frame(width: columnWidth, alignment: .leading)
                .offset(
                    y: min(
                        max(legibleTop - frame.minY, 0),
                        max(frame.height - SpeakerName.badgeSide, 0)))
            LineText(
                main: text.main, under: text.under, textSize: textSize, colour: line.voice.colour)
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(CaptionLines.area))
        } action: {
            frame = $0
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [line.speaker, text.main, text.under.map { "Translation: \($0)" }]
                .compactMap(\.self).joined(separator: ". "))
    }
}

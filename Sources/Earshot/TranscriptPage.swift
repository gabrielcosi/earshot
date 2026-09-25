import EarshotCapture
import EarshotKit
import SwiftUI

/// One transcript, live or saved, drawn the same way: its summary, then a card per line, and while
/// listening, the words still being recognized in a bar at the bottom.
struct TranscriptPage: View {
    let item: Navigation.Item
    @Environment(SessionController.self) private var controller
    @AppStorage(TranscriptSettings.textSize) private var storedSize = TranscriptTextSize.standard
    @AppStorage(TranscriptSettings.display) private var display = TranslationDisplay.both
    @State private var lines: [TranscriptLine] = []
    /// A saved transcript as read from its file; nil until read, or when it cannot be read.
    @State private var document: TranscriptDocument?
    @State private var unreadable = false
    /// The saved transcript's kept audio, when there is some.
    @State private var audio: URL?
    @State private var player = ClipPlayer()
    /// A line plays until the next one starts; a long monologue plays its first minute, and its
    /// text is right there for the rest.
    private static let longestClip = 60.0

    private var isLive: Bool { item == .live }

    private var file: URL? {
        switch item {
        case .live: controller.savedFile
        case .saved(let file): file
        }
    }

    private var summary: TranscriptDocument.Summary? {
        isLive ? controller.summary : document?.summary
    }

    private var listening: Bool {
        isLive && (controller.isRecording || controller.state == .starting)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if let summary {
                    SummaryView(summary: summary).padding(.bottom, 12)
                }
                ForEach(lines) { line in
                    TranscriptCard(
                        line: line, display: display, textSize: textSize,
                        playback: playback(for: line))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .defaultScrollAnchor(isLive ? .bottom : .top, for: .initialOffset)
        .followsLatest(listening, startsAtBottom: isLive, lineHeight: textSize)
        .safeAreaBar(edge: .top, spacing: 0) { failureBanner }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if listening {
                LiveBars(display: showsTranslation ? display : .original, textSize: textSize)
            }
        }
        .overlay { emptyState }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            TranscriptToolbar(file: file, isLive: isLive, showsTranslation: showsTranslation)
        }
        .onChange(of: controller.transcript.utterances, initial: true) { showLive() }
        .onChange(of: controller.names) { showLive() }
        .onChange(of: controller.rules) { showLive() }
        .task(id: controller.fileEdits) { read() }
        .onDisappear { player.stop() }
    }

    private var textSize: Double { TranscriptTextSize.clamped(storedSize) }

    /// The translation switch shows once there is something to switch between, or while
    /// translation is on for what is being heard.
    private var showsTranslation: Bool {
        lines.contains { $0.translation != nil } || (isLive && controller.translationEnabled)
    }

    private func showLive() {
        guard isLive else { return }
        lines = TranscriptLine.lines(
            in: controller.transcript, names: controller.names, rules: controller.rules)
    }

    private func read() {
        guard case .saved(let file) = item else { return }
        guard let markdown = try? String(contentsOf: file, encoding: .utf8) else {
            unreadable = true
            return
        }
        let document = TranscriptDocument(markdown: markdown)
        self.document = document
        lines = TranscriptLine.lines(in: document)
        let audio = TranscriptAudio.file(for: file)
        self.audio =
            FileManager.default.fileExists(atPath: audio.path(percentEncoded: false)) ? audio : nil
    }

    /// The user's title, else the time: the date is in the subtitle.
    private var title: String {
        switch item {
        case .live: listening ? "Listening now" : "Last session"
        case .saved(let file):
            document.flatMap { SavedTranscripts.title(of: file, document: $0) }
                ?? SavedTranscripts.date(of: file).formatted(date: .omitted, time: .shortened)
        }
    }

    private var subtitle: String {
        if listening {
            return "Started \(controller.startedAt.formatted(date: .omitted, time: .shortened))"
        }
        let started: String
        let length: Double?
        switch item {
        case .live:
            started = controller.startedAt.formatted(date: .abbreviated, time: .shortened)
            length = TranscriptLength.of(controller.transcript)
        case .saved(let file):
            let date = SavedTranscripts.date(of: file)
            let named = document.flatMap { SavedTranscripts.title(of: file, document: $0) } != nil
            started = date.formatted(date: .abbreviated, time: named ? .shortened : .omitted)
            length = document.flatMap(TranscriptLength.of)
        }
        return length.map { "\(started) · \(TranscriptLength.text($0))" } ?? started
    }

    @ViewBuilder private var failureBanner: some View {
        if let file, let failure = controller.failedSummaries[file],
            !controller.summarizing.contains(file)
        {
            SummaryFailureBanner(file: file, failure: failure)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if unreadable {
            ContentUnavailableView(
                "This transcript could not be read", systemImage: "exclamationmark.triangle",
                description: Text("It may have been moved or deleted."))
        } else if lines.isEmpty, listening {
            ContentUnavailableView(
                "Listening…", systemImage: "waveform",
                description: Text("Each line appears here once its speaker finishes it."))
        } else if lines.isEmpty, document != nil || isLive {
            ContentUnavailableView("Nothing transcribed", systemImage: "waveform")
        }
    }

    /// Kept audio plays each line; the session just ended has none to play here.
    private func playback(for line: TranscriptLine) -> TranscriptCard.Playback? {
        guard let audio else { return nil }
        return TranscriptCard.Playback(playing: player.playing == line.id) {
            let next = lines.drop { $0.id != line.id }.dropFirst().first?.start
            let seconds = min(
                (next ?? line.start + Self.longestClip) - line.start, Self.longestClip)
            player.toggle(line.id, file: audio, from: line.start, seconds: max(seconds, 1))
        }
    }
}

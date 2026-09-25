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
    /// The transcript as stored, kept current as the store changes; nil until read, and for a
    /// live session until its first line is stored.
    @State private var stored: StoredTranscript?
    @State private var unreadable = false
    /// The stored transcript's kept audio, when there is some.
    @State private var player: TranscriptPlayer?

    private var isLive: Bool { item == .live }

    /// The transcript in the store: for the live session, once its first line is stored.
    private var transcript: UUID? {
        switch item {
        case .live: controller.savedID
        case .saved(let transcript): transcript
        }
    }

    private var listening: Bool {
        isLive && (controller.isRecording || controller.state == .starting)
    }

    var body: some View {
        let playing = playingLine
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if let summary = stored?.summary {
                    SummaryView(summary: summary).padding(.bottom, 12)
                }
                ForEach(lines) { line in
                    TranscriptCard(
                        line: line, display: display, textSize: textSize,
                        playback: playback(for: line, playing: playing))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .defaultScrollAnchor(isLive ? .bottom : .top, for: .initialOffset)
        .followsLatest(listening, startsAtBottom: isLive, lineHeight: textSize)
        // The failure is about the whole transcript and comes first; the player sits right above
        // the lines it plays.
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                failureBanner
                exportBanner
                if let player { PlayerBar(player: player) }
            }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if listening {
                LiveBars(display: showsTranslation ? display : .original, textSize: textSize)
            }
        }
        .overlay { emptyState }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            TranscriptToolbar(
                transcript: transcript, isLive: isLive, audio: controller.keptAudio(stored),
                showsTranslation: showsTranslation)
        }
        .onChange(of: controller.transcript.utterances, initial: true) { showLive() }
        .onChange(of: controller.names) { showLive() }
        .onChange(of: controller.rules) {
            showLive()
            showStored()
        }
        .task(id: transcript) { await follow() }
        .onChange(of: controller.state) { checkExport() }
        .focusedSceneValue(\.transcriptPlayer, player)
        .focusedSceneValue(
            \.exportableTranscript, isLive && controller.state != .idle ? nil : transcript
        )
        .onDisappear { player?.pause() }
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

    /// Follows the transcript in the store, so names, a summary, kept audio, and edits show as
    /// soon as they are stored.
    private func follow() async {
        stored = nil
        guard let transcript else { return }
        checkExport()
        do {
            for try await view in controller.store.viewChanges(transcript) {
                stored = view
                showStored()
                if !isLive, player == nil {
                    player = controller.keptAudio(view).flatMap(TranscriptPlayer.init)
                }
            }
        } catch {
            unreadable = true
        }
    }

    private func showStored() {
        guard !isLive, let stored else { return }
        lines = TranscriptLine.lines(in: stored, rules: controller.rules)
        player?.starts = lines.map(\.start)
    }

    /// The Markdown file is checked when the transcript opens and once a session is over; it can
    /// change outside Earshot at any time.
    private func checkExport() {
        guard let transcript, !listening else { return }
        controller.checkExport(transcript)
    }

    /// The user's title, else the time: the date is in the subtitle.
    private var title: String {
        switch item {
        case .live: listening ? "Listening now" : "Last session"
        case .saved:
            stored.map { $0.title ?? $0.startedAt.formatted(date: .omitted, time: .shortened) }
                ?? ""
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
        case .saved:
            guard let stored else { return "" }
            started = stored.startedAt.formatted(
                date: .abbreviated, time: stored.title == nil ? .omitted : .shortened)
            length = stored.length
        }
        return length.map { "\(started) · \(TranscriptLength.text($0))" } ?? started
    }

    @ViewBuilder private var failureBanner: some View {
        if let transcript, let failure = controller.failedSummaries[transcript],
            !controller.summarizing.contains(transcript)
        {
            SummaryFailureBanner(transcript: transcript, failure: failure)
        }
    }

    @ViewBuilder private var exportBanner: some View {
        if let transcript, !listening {
            switch controller.exports[transcript] {
            case .edited(let file):
                StaleExportBanner(transcript: transcript, file: file, missing: false)
            case .missing(let file):
                StaleExportBanner(transcript: transcript, file: file, missing: true)
            default: EmptyView()
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if unreadable {
            ContentUnavailableView(
                "This transcript could not be read", systemImage: "exclamationmark.triangle",
                description: Text("Quit Earshot and open it again."))
        } else if lines.isEmpty, listening {
            ContentUnavailableView(
                "Listening…", systemImage: "waveform",
                description: Text("Each line appears here once its speaker finishes it."))
        } else if lines.isEmpty, stored != nil || isLive {
            ContentUnavailableView("Nothing transcribed", systemImage: "waveform")
        }
    }

    /// Kept audio plays from any line; the session just ended has none to play here.
    private func playback(for line: TranscriptLine, playing: String?) -> TranscriptCard.Playback? {
        guard let player else { return nil }
        return TranscriptCard.Playback(current: line.id == playing) {
            player.play(from: line.start)
        }
    }

    /// The line the player is in, once it has been played or moved; `starts` follows `lines`.
    private var playingLine: String? {
        guard let player, player.isPlaying || player.time > 0,
            let index = Playback.line(at: player.time, starts: player.starts),
            lines.indices.contains(index)
        else { return nil }
        return lines[index].id
    }
}

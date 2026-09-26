import EarshotKit
import SwiftUI

/// Start Listening or the live session on top, then the saved transcripts by day, and the way to
/// Settings.
struct TranscriptSidebar: View {
    let saved: SavedTranscripts
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @FocusedValue(\.transcriptPlayer) private var player
    /// The list, not Start Listening above it, takes focus when the window opens: with keyboard
    /// navigation on, the button would otherwise, and Space there would start a recording.
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: $navigation.selection) {
            if controller.hasLiveSession {
                LiveItem().tag(Navigation.Item.live)
            }
            ForEach(TranscriptDay.grouped(listed, by: \.startedAt), id: \.day) { group in
                Section(Self.heading(group.day)) {
                    ForEach(group.items) { entry in
                        SavedItem(entry: entry).tag(Navigation.Item.saved(entry.id))
                    }
                }
            }
        }
        .focused($listFocused)
        // The focused list takes Space before the Controls menu sees it (seen on screen), so it
        // plays and pauses here. Handled even with no player, so Space in the list never beeps.
        .onKeyPress(.space) {
            player?.toggle()
            return .handled
        }
        // Outside the list: a row there draws a prominent button through the sidebar's vibrancy,
        // a washed-out pink (#FFB0AE sampled) instead of Stop's red.
        .safeAreaBar(edge: .top) {
            if !controller.hasLiveSession {
                StartListeningRow()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
        .defaultFocus($listFocused, true)
        .safeAreaBar(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if let progress = controller.importProgress {
                    ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                        Text("Importing transcripts…")
                    } currentValueLabel: {
                        Text("\(progress.done) of \(progress.total)").monospacedDigit()
                    }
                    .controlSize(.small)
                }
                SettingsLink {
                    HStack {
                        Label("Settings…", systemImage: "gearshape")
                        Spacer()
                        Text("⌘,").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// The session being recorded is on top already; it joins the list when it ends.
    private var listed: [TranscriptStore.Entry] {
        guard controller.state != .idle, let live = controller.savedID else {
            return saved.entries
        }
        return saved.entries.filter { $0.id != live }
    }

    private static func heading(_ day: TranscriptDay) -> String {
        switch day {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .previousSevenDays: "Previous 7 Days"
        case .previousThirtyDays: "Previous 30 Days"
        case .month(let month): Calendar.current.standaloneMonthSymbols[month - 1]
        case .year(let year): String(year)
        }
    }
}

private struct LiveItem: View {
    @Environment(SessionController.self) private var controller

    var body: some View {
        HStack(spacing: 8) {
            switch controller.state {
            case .recording(let since):
                Image(systemName: "circle.fill").foregroundStyle(.red).imageScale(.small)
                Text("Listening now")
                Spacer()
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .starting:
                Image(systemName: "circle.fill").foregroundStyle(.red).imageScale(.small)
                Text("Listening now")
            case .stopping, .idle:
                Image(systemName: "waveform")
                Text("Finishing…")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SavedItem: View {
    let entry: TranscriptStore.Entry

    var body: some View {
        let time = entry.startedAt.formatted(date: .omitted, time: .shortened)
        let length = entry.length.map { TranscriptLength.text($0) }
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title ?? time).lineLimit(1)
            Text(
                [entry.title == nil ? nil : time, length].compactMap(\.self)
                    .joined(separator: " · ")
            )
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

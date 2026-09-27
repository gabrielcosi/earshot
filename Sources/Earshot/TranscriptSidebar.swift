import EarshotKit
import SwiftUI

/// Start Listening or the live session on top, then the saved transcripts by day, and the way to
/// Settings. A saved transcript is renamed in its row, and deleted from its context menu or with
/// Delete, as files are in Finder.
struct TranscriptSidebar: View {
    let saved: SavedTranscripts
    /// Asks before deleting what can be deleted of these.
    let delete: (Set<Navigation.Item>) -> Void
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.undoManager) private var undoManager
    @FocusedValue(\.transcriptPlayer) private var player
    /// The list, not Start Listening above it, takes focus when the window opens: with keyboard
    /// navigation on, the button would otherwise, and Space there would start a recording. A
    /// preference in a scope, not a focus binding on the list: bound, a rename field's focus went
    /// to the list instead. On macOS 27.0 a plain click on a row does not make the list first
    /// responder (FB24855120; a held click does), so Space and Delete work once the list has focus.
    @Namespace private var focusScope
    /// The transcript whose title is being edited in its row.
    @State private var renaming: UUID?

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: $navigation.selection) {
            if controller.hasLiveSession {
                LiveItem().tag(Navigation.Item.live)
            }
            ForEach(TranscriptDay.grouped(listed, by: \.startedAt), id: \.day) { group in
                Section(Self.heading(group.day)) {
                    ForEach(group.items) { entry in
                        SavedItem(entry: entry, renaming: renaming == entry.id) { title in
                            rename(entry, to: title)
                        }
                        .tag(Navigation.Item.saved(entry.id))
                    }
                }
            }
        }
        // Right-clicking a row outside the selection acts on that row alone, as in Finder.
        .contextMenu(forSelectionType: Navigation.Item.self) { items in
            // A plain button: `RenameButton` takes its action from the environment of the view
            // the menu belongs to, the whole list, which cannot tell which row was clicked.
            if let transcript = Self.single(items) {
                Button("Rename…") { renaming = transcript }
            }
            if !controller.deletable(items).isEmpty {
                Divider()
                Button("Delete", role: .destructive) { delete(items) }
            }
        }
        // Edit > Delete. The Delete keys do not reach it from the list (seen on screen), so they
        // are handled below, where Space is, once the list has focus.
        .onDeleteCommand {
            if renaming == nil { delete(navigation.selection) }
        }
        .prefersDefaultFocus(in: focusScope)
        // The focused list takes Space before the Controls menu sees it (seen on screen), so it
        // plays and pauses here. Handled even with no player, so Space in the list never beeps;
        // a title being edited types it.
        .onKeyPress(.space) {
            guard renaming == nil else { return .ignored }
            player?.toggle()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard renaming == nil else { return .ignored }
            delete(navigation.selection)
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
        .focusScope(focusScope)
    }

    /// The session being recorded is on top already; it joins the list when it ends.
    private var listed: [TranscriptStore.Entry] {
        saved.entries.filter { $0.id != controller.liveSavedID }
    }

    /// The one saved transcript among `items`, which can be renamed.
    private static func single(_ items: Set<Navigation.Item>) -> UUID? {
        guard items.count == 1, case .saved(let transcript) = items.first else { return nil }
        return transcript
    }

    /// Stores the title only when it was changed: the row shows the time for a transcript with
    /// Earshot's own title, and storing that would replace the file's heading with it. A row
    /// whose field closes because another row's rename started keeps what was typed, and leaves
    /// the other row's rename alone.
    private func rename(_ entry: TranscriptStore.Entry, to title: String?) {
        if renaming == entry.id { renaming = nil }
        guard let title, title != entry.label else { return }
        // Undo is for the transcript on screen: a row renamed from its context menu while another
        // is shown is not undone from that one.
        let shown = navigation.selected == .saved(entry.id)
        controller.setTitle(title, of: entry.id, undoManager: shown ? undoManager : nil)
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

extension TranscriptStore.Entry {
    /// The user's title, else the time: the day is the heading above it.
    var label: String { title ?? startedAt.formatted(date: .omitted, time: .shortened) }
}

private struct SavedItem: View {
    let entry: TranscriptStore.Entry
    let renaming: Bool
    /// The title typed, or nil when renaming was cancelled.
    let renamed: (String?) -> Void

    var body: some View {
        let time = entry.startedAt.formatted(date: .omitted, time: .shortened)
        let length = entry.length.map { TranscriptLength.text($0) }
        VStack(alignment: .leading, spacing: 2) {
            if renaming {
                TitleField(title: entry.label, done: renamed)
            } else {
                Text(entry.label).lineLimit(1)
            }
            Text(
                [entry.title == nil ? nil : time, length].compactMap(\.self)
                    .joined(separator: " · ")
            )
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        // One element to read, but the title field stays its own while it is being edited.
        .accessibilityElement(children: renaming ? .contain : .combine)
    }
}

/// A row's title, edited in place: Return saves, Escape puts it back, and clicking elsewhere saves,
/// as a file's name does in Finder.
private struct TitleField: View {
    /// The title typed, or nil when cancelled; called once.
    let done: (String?) -> Void
    @State private var text: String
    @State private var finished = false
    @FocusState private var focused: Bool

    init(title: String, done: @escaping (String?) -> Void) {
        self.done = done
        _text = State(initialValue: title)
    }

    var body: some View {
        TextField("Title", text: $text)
            .labelsHidden()
            .focused($focused)
            // Asked for once the context menu that started the rename has closed: closing it gives
            // focus back to the list, which would end the rename as soon as it began.
            .onAppear { Task { focused = true } }
            .onSubmit { finish(text) }
            .onExitCommand { finish(nil) }
            .onChange(of: focused) {
                if !focused { finish(text) }
            }
            // Renaming another row takes this field away without a focus change reaching it.
            .onDisappear { finish(text) }
    }

    private func finish(_ title: String?) {
        guard !finished else { return }
        finished = true
        done(title)
    }
}

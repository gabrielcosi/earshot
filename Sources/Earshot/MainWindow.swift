import EarshotKit
import SwiftUI
@preconcurrency import Translation

/// What the windows show; the menu bar sets it when it opens one.
@Observable
final class Navigation {
    enum Item: Hashable {
        /// The session being started, recorded, or stopped.
        case live
        /// A transcript in the store.
        case saved(UUID)
    }

    enum SettingsTab: Hashable {
        case general
        case words
        case microphone
        case models
        case summaries
        case about
    }

    /// What the sidebar has selected: usually one item, or several to delete together.
    var selection: Set<Item> = []
    var settingsTab = SettingsTab.general
    /// Set when Earshot is opened again while it runs with no window, or by a view outside any
    /// scene, such as the captions overlay; the menu bar label opens the main window, since
    /// neither can.
    var windowRequested = false
    /// The same for Settings, at `settingsTab`.
    var settingsRequested = false
    /// The same for setup, at this step.
    var setupRequested: SetupStep?
    /// A stored transcript to open with the speakers panel: set when a session stops.
    var naming: UUID?
    /// The speakers panel beside the transcript, opened and closed by Name Speakers.
    var showsSpeakers = false

    /// The one item selected; nil with none or several.
    var selected: Item? { selection.count == 1 ? selection.first : nil }
}

extension Navigation.Item {
    /// The transcript in the store; the live session's is `live`, once its first line is stored.
    func transcript(live: UUID?) -> UUID? {
        switch self {
        case .live: live
        case .saved(let transcript): transcript
        }
    }
}

/// The transcripts: the live session and the saved ones in the sidebar, the selected one beside.
struct MainWindow: View {
    @Environment(Navigation.self) private var navigation
    @Environment(SessionController.self) private var controller
    @Environment(\.undoManager) private var undoManager
    @State private var saved = SavedTranscripts()
    /// The transcript last selected, selected again when the window opens. App storage, not
    /// scene storage: SwiftUI destroys a scene's stored state when its window is closed on macOS,
    /// and Earshot's one window is closed and reopened all the time.
    @AppStorage("lastTranscript") private var lastTranscript = ""
    /// The transcripts Delete asks about, while it asks.
    @State private var deleting: Set<UUID> = []
    /// Deleted from this window: the sidebar's list takes a moment to follow the store, and none
    /// of them is selected again meanwhile.
    @State private var deleted: Set<UUID> = []

    var body: some View {
        NavigationSplitView {
            TranscriptSidebar(saved: saved, delete: askToDelete)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            detail
                // Several selected hide the panel, and it comes back with one: they do not
                // finish naming the transcript it was open on (`SpeakersPanel.close`).
                .inspector(isPresented: speakersShown) {
                    SpeakersPanel(transcript: shownTranscript)
                        .id(shownTranscript)
                        // The approved design's width.
                        .inspectorColumnWidth(ideal: 320)
                }
        }
        .frame(minWidth: 640, minHeight: 420)
        // Here rather than on a view inside, so the prompt shows whatever is selected.
        .translationTask(controller.downloadRequest) { session in
            let (source, target) = (session.sourceLanguage, session.targetLanguage)
            controller.translationLog.download(
                .started, from: source?.minimalIdentifier, to: target?.minimalIdentifier)
            do {
                try await session.prepareTranslation()
                controller.downloadFinished(from: source, to: target)
            } catch {
                controller.downloadFailed(from: source, to: target, error)
            }
        }
        .task { await saved.follow(controller.store) }
        .onAppear {
            controller.preferences.openWindows += 1
            takeNamingRequest()
        }
        .onDisappear {
            controller.preferences.openWindows -= 1
            controller.finishNaming()
        }
        .onChange(of: navigation.naming) { takeNamingRequest() }
        // Undo is for the transcript on screen. The live session keeps its transcript when it
        // stops and opens as a saved one, so that is no change. Naming the session that just
        // ended is done once another transcript is shown; several selected show none, and
        // naming waits.
        .onChange(of: shownTranscript) { _, shown in
            undoManager?.removeAllActions()
            if let shown, let awaiting = controller.awaitingNaming, awaiting != shown {
                controller.finishNaming(awaiting)
            }
        }
        .onChange(of: navigation.selection) {
            if case .saved(let transcript) = navigation.selected {
                lastTranscript = transcript.uuidString
            }
            // A start that failed, or a session with nothing said, leaves nothing selected: back
            // to the transcript the reader was on.
            restoreSelection()
        }
        .onChange(of: saved.entries.map(\.id)) { _, listed in
            let listed = Set(listed)
            let gone = navigation.selection.filter { item in
                guard case .saved(let transcript) = item else { return false }
                return !listed.contains(transcript)
            }
            if !gone.isEmpty { navigation.selection.subtract(gone) }
            restoreSelection()
        }
        .onChange(of: controller.state) {
            if controller.isRecording { navigation.selection = [.live] }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } }),
            presenting: deleting
        ) { targets in
            Button("Delete", role: .destructive) { Task { await delete(targets) } }
            Button("Cancel", role: .cancel) {}
        } message: { targets in
            Text(
                targets.count == 1
                    ? "The transcript and its kept audio are removed from Earshot. Its Markdown copy in your transcripts folder is kept."
                    : "The transcripts and their kept audio are removed from Earshot. Markdown copies in your transcripts folder are kept."
            )
        }
        .alert(
            "Earshot could not start listening",
            isPresented: Binding(
                get: { controller.startFailure != nil },
                set: { if !$0 { controller.startFailure = nil } }),
            presenting: controller.startFailure
        ) { problem in
            let fix = ProblemFix(controller: controller, navigation: navigation, dismiss: {})
            // The first button is the default: a fix when there is one, else OK.
            if let action = fix.action(for: problem), action.fixes {
                Button(action.title, action: action.run)
                Button("OK", role: .cancel) {}
            } else {
                Button("OK") {}
                if let action = fix.action(for: problem) {
                    Button(action.title, action: action.run)
                }
            }
        } message: { problem in
            Text(problem.message())
        }
    }

    /// The live session is shown only while one runs; once it stops, its stored transcript is,
    /// here rather than when the selection moves (`MenuBarLabel`), so the transcript on screen
    /// never passes through none: that would finish naming it before its speakers are named.
    private var shown: Navigation.Item? {
        guard navigation.selection.count <= 1 else { return nil }
        let item = navigation.selected ?? (controller.isRecording ? .live : nil)
        guard item == .live, !controller.hasLiveSession else { return item }
        return controller.savedID.map(Navigation.Item.saved)
    }

    private var shownTranscript: UUID? { shown?.transcript(live: controller.savedID) }

    @ViewBuilder private var detail: some View {
        switch shown {
        case .live:
            TranscriptPage(item: .live)
        case .saved(let transcript):
            TranscriptPage(item: .saved(transcript)).id(transcript)
        case nil:
            if navigation.selection.count > 1 {
                // Counted as Delete counts them: the session being recorded is not one of them.
                let targets = controller.deletable(navigation.selection)
                ContentUnavailableView {
                    Label(
                        targets.count == 1
                            ? "1 Transcript Selected" : "\(targets.count) Transcripts Selected",
                        systemImage: "doc.on.doc")
                } actions: {
                    Button("Delete", role: .destructive) { askToDelete(navigation.selection) }
                        .disabled(targets.isEmpty)
                }
            } else if saved.unreadable {
                ContentUnavailableView(
                    "Earshot could not read its transcripts",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Quit Earshot and open it again."))
            } else if saved.entries.isEmpty, !controller.hasLiveSession, !controller.importing {
                ContentUnavailableView(
                    "No transcripts yet", systemImage: "waveform",
                    description: Text(
                        "Start listening from the sidebar, with ⌘N, or from the ear in the menu bar."
                    ))
            } else {
                ContentUnavailableView(
                    "No transcript selected", systemImage: "waveform",
                    description: Text("Choose a transcript in the sidebar."))
            }
        }
    }

    /// A session that just stopped opens selected, with the speakers panel.
    private func takeNamingRequest() {
        guard let transcript = navigation.naming else { return }
        navigation.naming = nil
        navigation.selection = [.saved(transcript)]
        navigation.showsSpeakers = true
    }

    /// Nothing selected: the transcript selected last time, or the newest if that one is gone.
    /// A live session and a naming request choose their own.
    private func restoreSelection() {
        guard navigation.selection.isEmpty, navigation.naming == nil, !controller.isRecording
        else { return }
        let entries = saved.entries.filter { !deleted.contains($0.id) }
        let transcript =
            entries.first { $0.id.uuidString == lastTranscript }?.id
            ?? entries.max { $0.startedAt < $1.startedAt }?.id
        if let transcript { navigation.selection = [.saved(transcript)] }
    }

    private var speakersShown: Binding<Bool> {
        Binding(
            get: { navigation.showsSpeakers && navigation.selection.count <= 1 },
            // Hidden for several selected, a write back of false is not the reader closing it.
            set: { if navigation.selection.count <= 1 { navigation.showsSpeakers = $0 } })
    }

    // MARK: - Deleting

    /// Asks before deleting what can be of `items`: the session being recorded cannot.
    private func askToDelete(_ items: Set<Navigation.Item>) {
        deleting = controller.deletable(items)
    }

    private var deleteTitle: String {
        guard deleting.count == 1 else { return "Delete \(deleting.count) transcripts?" }
        let entry = saved.entries.first { deleting.contains($0.id) }
        return entry.map { "Delete “\($0.label)”?" } ?? "Delete this transcript?"
    }

    /// Deletes the transcripts; a selection they were in moves on to the next row, as Mail and
    /// Notes do. Deleting cannot be undone, so nothing before it can be either: Undo would change
    /// a transcript the reader may no longer be looking at.
    private func delete(_ targets: Set<UUID>) async {
        // Without transcripts deleted just before, which the list may still hold.
        let order = saved.entries.map(\.id).filter {
            $0 != controller.liveSavedID && !deleted.contains($0)
        }
        let naming = controller.awaitingNaming.map(targets.contains) ?? false
        guard await controller.delete(targets) else { return }
        deleted.formUnion(targets)
        if let last = UUID(uuidString: lastTranscript), targets.contains(last) {
            lastTranscript = ""
        }
        if naming || navigation.naming.map(targets.contains) == true {
            navigation.naming = nil
            navigation.showsSpeakers = false
        }
        undoManager?.removeAllActions()
        let items = Set(targets.map(Navigation.Item.saved))
        guard !navigation.selection.isDisjoint(with: items) else { return }
        let remaining = navigation.selection.subtracting(items)
        navigation.selection =
            if !remaining.isEmpty {
                remaining
            } else if let next = ListSelection.next(afterDeleting: targets, in: order) {
                [.saved(next)]
            } else {
                []
            }
    }
}

extension SessionController {
    /// A session is starting, recording, or stopping: the sidebar's live row is shown.
    var hasLiveSession: Bool { state != .idle }

    /// The session's transcript while the live row stands for it, so it is not a saved one yet.
    var liveSavedID: UUID? { hasLiveSession ? savedID : nil }
}

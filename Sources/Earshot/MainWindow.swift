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

    var selection: Item?
    var settingsTab = SettingsTab.general
    /// Set when Earshot is opened again while it runs with no window, or by a view outside any
    /// scene, such as the captions overlay; the menu bar label opens the main window, since
    /// neither can.
    var windowRequested = false
    /// The same for Settings, at `settingsTab`.
    var settingsRequested = false
    /// A stored transcript to open with the speakers panel: set when a session stops.
    var naming: UUID?
    /// The speakers panel beside the transcript, opened and closed by Name Speakers.
    var showsSpeakers = false
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

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            TranscriptSidebar(saved: saved)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            detail
                .inspector(isPresented: $navigation.showsSpeakers) {
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
        // stops and opens as a saved one, so that is no change.
        .onChange(of: shownTranscript) { old, _ in
            undoManager?.removeAllActions()
            if let old { controller.finishNaming(old) }
        }
        .onChange(of: navigation.selection) {
            if case .saved(let transcript) = navigation.selection {
                lastTranscript = transcript.uuidString
            }
            // A start that failed, or a session with nothing said, leaves nothing selected: back
            // to the transcript the reader was on.
            restoreSelection()
        }
        .onChange(of: saved.entries.map(\.id)) { restoreSelection() }
        .onChange(of: controller.state) {
            if controller.isRecording { navigation.selection = .live }
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
        let item = navigation.selection ?? (controller.isRecording ? .live : nil)
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
            if saved.unreadable {
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
        navigation.selection = .saved(transcript)
        navigation.showsSpeakers = true
    }

    /// Nothing selected: the transcript selected last time, or the newest if that one is gone.
    /// A live session and a naming request choose their own.
    private func restoreSelection() {
        guard navigation.selection == nil, navigation.naming == nil, !controller.isRecording
        else { return }
        let entries = saved.entries
        let transcript =
            entries.first { $0.id.uuidString == lastTranscript }?.id
            ?? entries.max { $0.startedAt < $1.startedAt }?.id
        if let transcript { navigation.selection = .saved(transcript) }
    }
}

extension SessionController {
    /// A session is starting, recording, or stopping: the sidebar's live row is shown.
    var hasLiveSession: Bool { state != .idle }
}

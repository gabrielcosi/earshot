import SwiftUI
@preconcurrency import Translation

/// What the windows show; the menu bar sets it when it opens one.
@Observable
final class Navigation {
    enum Item: Hashable {
        /// The session in memory: being recorded, or the last one.
        case live
        case saved(URL)
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
    /// Set when Earshot is opened again while it runs with no window; the menu bar label opens
    /// the main window, since the app delegate cannot.
    var windowRequested = false
    /// A saved transcript to open with its naming sheet: set when a session stops, and by Name
    /// Speakers.
    var naming: URL?
}

/// The transcripts: the live session and the saved ones in the sidebar, the selected one beside.
struct MainWindow: View {
    @Environment(Navigation.self) private var navigation
    @Environment(SessionController.self) private var controller
    @State private var saved = SavedTranscripts()
    @State private var naming: NamingTarget?
    /// The transcript last selected, selected again when the window opens. App storage, not
    /// scene storage: SwiftUI destroys a scene's stored state when its window is closed on macOS,
    /// and Earshot's one window is closed and reopened all the time.
    @AppStorage("lastTranscript") private var lastTranscript = ""

    var body: some View {
        NavigationSplitView {
            TranscriptSidebar(saved: saved)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            detail
        }
        .frame(minWidth: 640, minHeight: 420)
        .sheet(item: $naming) { target in NamingView(file: target.file) }
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
        .onAppear {
            controller.preferences.openWindows += 1
            reload()
            takeNamingRequest()
        }
        .onDisappear { controller.preferences.openWindows -= 1 }
        .onChange(of: navigation.naming) { takeNamingRequest() }
        .onChange(of: controller.savedFile) { reload() }
        .onChange(of: controller.fileEdits) { reload() }
        .onChange(of: controller.preferences.transcriptsFolder) { reload() }
        .onChange(of: navigation.selection) {
            if case .saved(let file) = navigation.selection {
                lastTranscript = file.path(percentEncoded: false)
            }
        }
        .onChange(of: saved.entries.map(\.file)) { restoreSelection() }
        .onChange(of: controller.state) {
            if controller.isRecording { navigation.selection = .live }
            if controller.state == .idle { reload() }
        }
    }

    /// The live session until one starts, and after a session with nothing said, is not listed.
    private var shown: Navigation.Item? {
        let item = navigation.selection ?? (controller.isRecording ? .live : nil)
        return item == .live && !controller.hasLiveSession ? nil : item
    }

    @ViewBuilder private var detail: some View {
        switch shown {
        case .live:
            TranscriptPage(item: .live)
        case .saved(let file):
            TranscriptPage(item: .saved(file)).id(file)
        case nil:
            if saved.entries.isEmpty, !controller.hasLiveSession {
                ContentUnavailableView(
                    "No transcripts yet", systemImage: "waveform",
                    description: Text("Start listening from the ear in the menu bar."))
            } else {
                ContentUnavailableView(
                    "No transcript selected", systemImage: "waveform",
                    description: Text("Choose a transcript in the sidebar."))
            }
        }
    }

    /// A session that just stopped opens selected, with its naming sheet.
    private func takeNamingRequest() {
        guard let file = navigation.naming else { return }
        navigation.naming = nil
        reload()
        navigation.selection = .saved(file)
        naming = NamingTarget(file: file)
    }

    /// Nothing selected: the transcript selected last time, or the newest if that one is gone.
    /// A live session and a naming request choose their own.
    private func restoreSelection() {
        guard navigation.selection == nil, navigation.naming == nil, !controller.isRecording
        else { return }
        let entries = saved.entries
        let file =
            entries.first { $0.file.path(percentEncoded: false) == lastTranscript }?.file
            ?? entries.max { $0.date < $1.date }?.file
        if let file { navigation.selection = .saved(file) }
    }

    private func reload() {
        saved.reload(controller.preferences.transcriptsFolder)
    }
}

extension SessionController {
    /// A session is recording, or one has ended and is still in memory.
    var hasLiveSession: Bool {
        state != .idle || !transcript.utterances.isEmpty
    }
}

private struct NamingTarget: Identifiable {
    let file: URL
    var id: URL { file }
}

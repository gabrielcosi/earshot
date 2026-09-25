import SwiftUI
@preconcurrency import Translation

/// What the main window shows; the menu bar sets it when it opens the window.
@Observable
final class Navigation {
    enum Section: Hashable {
        case transcripts
        case words
        case settings
        case about
    }

    var section: Section? = .transcripts
    /// Opens the model library sheet over Settings.
    var browsingModels = false
    /// A saved transcript to open with its naming sheet, set when a session stops.
    var naming: URL?
}

struct MainWindow: View {
    @Environment(Navigation.self) private var navigation
    @Environment(SessionController.self) private var controller

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            List(selection: $navigation.section) {
                Label("Transcripts", systemImage: "waveform").tag(Navigation.Section.transcripts)
                Label("Words", systemImage: "character.book.closed").tag(Navigation.Section.words)
                Label("Settings", systemImage: "gearshape").tag(Navigation.Section.settings)
                Label("About", systemImage: "info.circle").tag(Navigation.Section.about)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch navigation.section ?? .transcripts {
            case .transcripts: TranscriptsView()
            case .words: WordsView()
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        // Here rather than on a view inside, so the prompt shows whichever section is open.
        .translationTask(controller.downloadRequest) { session in
            let (source, target) = (session.sourceLanguage, session.targetLanguage)
            do {
                try await session.prepareTranslation()
                controller.downloadFinished(from: source, to: target)
            } catch {
                controller.downloadFailed(from: source, to: target, error)
            }
        }
        .onAppear { controller.preferences.mainWindowOpen = true }
        .onDisappear { controller.preferences.mainWindowOpen = false }
    }
}

struct AboutView: View {
    @Environment(Updater.self) private var updater

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Earshot").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text(
                "Transcribes calls, meetings, and anything else the Mac plays, on this Mac, with NVIDIA Nemotron models running in NeMo-Speech.cpp, and translates with Apple's on-device Translation."
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            .foregroundStyle(.secondary)
            if updater.isAvailable {
                @Bindable var updater = updater
                Button("Check for Updates…") { updater.check() }
                    .disabled(!updater.canCheck)
                    .padding(.top, 8)
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
            }
            if let licenses = Bundle.main.url(forResource: "Licenses", withExtension: nil) {
                Button("Licenses") { NSWorkspace.shared.activateFileViewerSelecting([licenses]) }
                    .buttonStyle(.link)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}

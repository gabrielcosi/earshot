import AppKit
import EarshotKit
import SwiftUI

@main
struct EarshotApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(delegate.controller)
                .environment(delegate.navigation)
        } label: {
            MenuBarLabel()
                .environment(delegate.controller)
                .environment(delegate.navigation)
        }
        .menuBarExtraStyle(.window)

        Window("Earshot", id: "main") {
            MainWindow()
                .environment(delegate.controller)
                .environment(delegate.navigation)
                .environment(delegate.updater)
        }
        .defaultSize(width: 960, height: 680)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = SessionController()
    let navigation = Navigation()
    let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Recording.removeLeftovers()
        controller.preferences.applyDockIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.discardLastRecording()
        controller.engine.stop()
    }
}

/// The menu bar icon. It exists from launch, so it also opens Settings when no model is
/// downloaded yet.
struct MenuBarLabel: View {
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.glyph(recording: controller.isRecording))
            .task {
                if controller.preferences.keepEngineLoaded { controller.prewarm() }
                guard controller.library.selection == nil else { return }
                navigation.section = .settings
                navigation.browsingModels = true
                openWindow(id: "main")
                NSApp.activate()
            }
    }
}

extension MenuBarLabel {
    /// The app icon's ear and level bars as a template image; recording swaps the bars for a dot.
    /// Outside a bundle (`swift run`) there is no glyph, so a symbol stands in.
    static func glyph(recording: Bool) -> NSImage {
        let name = recording ? "MenuBarRecording" : "MenuBarIcon"
        guard let image = Bundle.main.image(forResource: name) else {
            let symbol = recording ? "record.circle" : "waveform"
            return NSImage(systemSymbolName: symbol, accessibilityDescription: "Earshot")
                ?? NSImage()
        }
        image.isTemplate = true
        image.accessibilityDescription = recording ? "Earshot, recording" : "Earshot"
        return image
    }
}

/// The hot actions. Everything else lives in the main window.
struct MenuContent: View {
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var controller = controller
        @Bindable var preferences = controller.preferences
        VStack(alignment: .leading, spacing: 12) {
            status
            if controller.library.selection == nil, !controller.isRecording {
                Text("Earshot needs a transcription model before it can listen.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    navigation.browsingModels = true
                    show(.settings)
                } label: {
                    Label("Set Up Models…", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: toggle) {
                    Label(
                        controller.isRecording ? "Stop" : "Start listening",
                        systemImage: controller.isRecording ? "stop.fill" : "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(controller.isRecording ? .red : .accentColor)
                .disabled(controller.state == .starting || controller.state == .stopping)
            }

            Toggle(isOn: $preferences.useMicrophone) {
                Label("Include my microphone", systemImage: "mic")
            }
            .disabled(controller.state != .idle)
            Toggle(isOn: $preferences.cancelSpeakerEcho) {
                Label("Cancel speaker echo", systemImage: "speaker.wave.2")
            }
            .disabled(!preferences.useMicrophone || controller.state != .idle)
            LabeledContent("Listening to") { SourcesMenu().fixedSize() }
            LabeledContent("Spoken") { SpokenLanguagesMenu().fixedSize() }
            Toggle(
                "Translate into \(Languages.displayName(controller.primaryLanguage))",
                isOn: $controller.translationEnabled)

            if let error = controller.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Open Earshot") { show(.transcripts) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear { controller.prewarm() }
        .onDisappear { controller.scheduleUnload() }
    }

    @ViewBuilder private var status: some View {
        switch controller.state {
        case .idle: Text("Idle").foregroundStyle(.secondary)
        case .starting: Text("Starting engine…").foregroundStyle(.secondary)
        case .stopping: Text("Finishing…").foregroundStyle(.secondary)
        case .recording(let since):
            HStack {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(.red)
                if controller.engineLoading {
                    ProgressView().controlSize(.small)
                    Text("Loading models, the transcript will catch up")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggle() {
        Task {
            if controller.isRecording {
                await controller.stop()
                if let file = controller.savedFile,
                    let markdown = try? String(contentsOf: file, encoding: .utf8),
                    !SpeakerNames.speakers(in: markdown).isEmpty
                {
                    navigation.naming = file
                    show(.transcripts)
                } else {
                    controller.sessionFinished()
                }
                return
            }
            show(.transcripts)
            await controller.start()
        }
    }

    private func show(_ section: Navigation.Section) {
        navigation.section = section
        openWindow(id: "main")
        NSApp.activate()
    }
}

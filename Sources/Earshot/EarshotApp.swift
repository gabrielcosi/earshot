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
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            TranscriptCommands(updater: delegate.updater)
            PlaybackCommands()
        }

        Settings {
            SettingsWindow()
                .environment(delegate.controller)
                .environment(delegate.navigation)
                .environment(delegate.updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = SessionController()
    let navigation = Navigation()
    let updater = Updater()

    /// A second copy would delete the recordings of the first one's session as it launched.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let id = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .contains(where: { $0 != .current })
        else { return }
        let alert = NSAlert()
        alert.messageText = "Earshot is already running"
        alert.informativeText = "Look for the ear in the menu bar."
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Recording.removeLeftovers()
        controller.preferences.applyDockIcon()
        TranscriptCommands.zoomInWithEquals()
    }

    /// Opening Earshot again, from Finder, Spotlight, or the Dock, shows its window, as any app
    /// does. False tells AppKit this was handled; with a window already visible, AppKit brings it
    /// forward itself.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        navigation.windowRequested = true
        return false
    }

    /// A session ends before the app does: the engine does not exit while the session's
    /// connections are open, and the transcript is saved.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.state != .idle else { return .terminateNow }
        Task {
            await controller.finishForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(
            nsImage: Self.glyph(
                recording: controller.isRecording, attention: controller.needsAttention)
        )
        .task {
            if controller.preferences.keepEngineLoaded { controller.prewarm() }
            guard controller.library.selection == nil else { return }
            navigation.settingsTab = .models
            openSettings()
            NSApp.activate()
        }
        .onChange(of: navigation.windowRequested) {
            guard navigation.windowRequested else { return }
            navigation.windowRequested = false
            openWindow(id: "main")
            NSApp.activate()
        }
        // The label lives as long as the app, so a session that ends while the menu is closed
        // still gets its naming sheet, the next time the window opens.
        .onChange(of: controller.namingRequest) {
            guard let request = controller.namingRequest else { return }
            controller.namingRequest = nil
            navigation.naming = request.file
            guard request.opensWindow else { return }
            openWindow(id: "main")
            NSApp.activate()
        }
    }
}

extension MenuBarLabel {
    /// The app icon's ear and level bars as a template image; recording swaps the bars for a dot,
    /// and a session that ended on its own adds a warning mark. Outside a bundle (`swift run`)
    /// there is no glyph, so a symbol stands in.
    static func glyph(recording: Bool, attention: Bool) -> NSImage {
        let name = recording ? "MenuBarRecording" : "MenuBarIcon"
        let symbol = recording ? "record.circle" : "waveform"
        guard
            let image = Bundle.main.image(forResource: name)
                ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else { return NSImage() }
        let glyph = attention ? marked(image) : image
        glyph.isTemplate = true
        glyph.accessibilityDescription =
            attention ? "Earshot, needs attention" : recording ? "Earshot, recording" : "Earshot"
        return glyph
    }

    /// The glyph with a warning mark in its lower right corner, cut out of the glyph so the two
    /// stay apart in a template image, which keeps only alpha.
    private static func marked(_ glyph: NSImage) -> NSImage {
        let mark = NSImage(
            systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
        return NSImage(size: glyph.size, flipped: false) { bounds in
            glyph.draw(in: bounds)
            let side = bounds.height / 2
            let corner = NSRect(x: bounds.maxX - side, y: bounds.minY, width: side, height: side)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: corner.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            mark?.draw(in: corner)
            return true
        }
    }
}

/// The hot actions. Everything else lives in the main window.
struct MenuContent: View {
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    /// Closes this panel: an action that brings up a window takes it out of the way.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var controller = controller
        @Bindable var preferences = controller.preferences
        VStack(alignment: .leading, spacing: 12) {
            status
            ForEach(controller.shownProblems) { problem in
                ProblemRow(problem: problem)
            }
            if controller.library.selection == nil, !controller.isRecording {
                Button {
                    navigation.settingsTab = .models
                    dismiss()
                    openSettings()
                    NSApp.activate()
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
            LabeledContent("Translate into") { TranslationMenu().fixedSize() }

            Divider()
            HStack {
                Button("Open Earshot", action: showWindow)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            controller.needsAttention = false
            controller.prewarm()
        }
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
                return
            }
            navigation.selection = .live
            showWindow()
            await controller.start()
        }
    }

    private func showWindow() {
        dismiss()
        openWindow(id: "main")
        NSApp.activate()
    }
}

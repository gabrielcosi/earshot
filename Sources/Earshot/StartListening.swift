import AppKit
import SwiftUI

/// Starts a session from wherever it is asked for: the menu bar, the sidebar's first row, or
/// File > Start Listening. With no model chosen yet, Settings opens on Models instead. Otherwise
/// the window opens on the live session and listening starts; what goes wrong is reported to
/// the menu's problems.
struct StartListening {
    let controller: SessionController
    let navigation: Navigation
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction

    /// Nothing is started while a session is starting, running, or stopping.
    var isPossible: Bool { controller.state == .idle }

    func setUpModels() {
        navigation.settingsTab = .models
        openSettings()
        NSApp.activate()
    }

    func callAsFunction() async {
        guard isPossible else { return }
        guard controller.library.selection != nil else { return setUpModels() }
        navigation.selection = .live
        openWindow(id: "main")
        NSApp.activate()
        await controller.start()
        // A start that failed leaves nothing to show; the window goes back to where it was.
        if controller.state == .idle { navigation.selection = nil }
    }
}

/// File > Start Listening, where Mac apps keep New, with Voice Memos' ⌘N for a new recording:
/// Earshot has one window and no document to make, so ⌘N is free. While recording the same item
/// stops, on ⌘., the key AppKit binds to stopping what is under way (`cancelOperation(_:)`), with
/// no menu command of its own. QuickTime's ⌃⌘Esc is left alone: it stops the system's screen
/// recording, which may be running during the same meeting.
struct StartListeningCommands: Commands {
    let controller: SessionController
    let navigation: Navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if controller.isRecording {
                Button("Stop Listening") { Task { await controller.stop() } }
                    .keyboardShortcut(".")
            } else {
                let start = StartListening(
                    controller: controller, navigation: navigation, openWindow: openWindow,
                    openSettings: openSettings)
                Button("Start Listening") { Task { await start() } }
                    .keyboardShortcut("n")
                    .disabled(!start.isPossible)
            }
        }
    }
}

/// Above the sidebar's list while nothing is being recorded, where the live session's row goes
/// once it starts. Never a row of the list, so it never becomes the selection; Stop is in the
/// live transcript.
struct StartListeningRow: View {
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let start = StartListening(
            controller: controller, navigation: navigation, openWindow: openWindow,
            openSettings: openSettings)
        Button {
            Task { await start() }
        } label: {
            Label("Start Listening", systemImage: "record.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }
}

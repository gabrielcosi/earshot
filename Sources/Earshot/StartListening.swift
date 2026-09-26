import AppKit
import SwiftUI

/// Starts a session from wherever it is asked for: the menu bar, the sidebar's first row, or
/// File > Start Listening. With no model chosen yet, Settings opens on Models instead. Otherwise
/// the window opens on the live session and listening starts; what goes wrong is reported to
/// the menu's problems. With the captions overlay on, the overlay is where the session shows: a
/// start from the menu bar opens no window, and one from the window closes it, so the call behind
/// it comes forward.
struct StartListening {
    let controller: SessionController
    let navigation: Navigation
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction
    /// Set when started from the window, to close it.
    var dismissWindow: DismissWindowAction?

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
        let captions = controller.preferences.showsCaptions
        navigation.selection = .live
        if !captions {
            openWindow(id: "main")
            NSApp.activate()
        }
        await controller.start()
        // A start that failed leaves nothing to show; the window goes back to where it was, and
        // stays in front with its alert.
        if controller.state == .idle {
            navigation.selection = nil
        } else if captions, let dismissWindow {
            // Capture has started. A failure from here on, such as the engine not loading, ends
            // the session on its own, and the overlay says why. Hiding alone would not last:
            // opening the menu bar's window activates Earshot, which unhides its windows, so the
            // window is closed; hiding then hands the call its activation back.
            dismissWindow(id: "main")
            NSApp.hide(nil)
        }
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
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if controller.isRecording {
                Button("Stop Listening") { Task { await controller.stop() } }
                    .keyboardShortcut(".")
            } else {
                let start = StartListening(
                    controller: controller, navigation: navigation, openWindow: openWindow,
                    openSettings: openSettings, dismissWindow: dismissWindow)
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
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let start = StartListening(
            controller: controller, navigation: navigation, openWindow: openWindow,
            openSettings: openSettings, dismissWindow: dismissWindow)
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

import AppKit
import EarshotKit
import SwiftUI

/// One problem in the menu, with the action that fixes or explains it where there is one.
struct ProblemRow: View {
    let problem: Problem
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(problem.isTranslation ? Color.secondary : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(problem.message())
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.title, action: action.run).controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // No model is not a report but the state of the library: it goes once a model is
            // chosen, and the button under it sets one up.
            if problem != .noModel {
                Button("Dismiss", systemImage: "xmark") { controller.problems.dismiss(problem) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Dismiss")
            }
        }
        .font(.callout)
    }

    private var symbol: String {
        switch problem {
        case .translationNeedsDownload: "arrow.down.circle"
        case .translationUnsupported: "info.circle"
        default: "exclamationmark.triangle"
        }
    }

    private var action: ProblemFix.Action? {
        ProblemFix(
            controller: controller, navigation: navigation, openWindow: openWindow,
            openSettings: openSettings, dismiss: { dismiss() }
        ).action(for: problem)
    }
}

/// What fixes or explains a problem, for its row in the menu and the window's alert. `dismiss`
/// closes what shows it, when an action brings up another window.
struct ProblemFix {
    struct Action {
        let title: String
        let run: () -> Void
        /// It fixes the problem, rather than showing where to look: the alert's default button.
        var fixes = true
    }

    let controller: SessionController
    let navigation: Navigation
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction
    let dismiss: () -> Void

    /// `.noModel` has none: the menu's main button sets up models while none is selected.
    func action(for problem: Problem) -> Action? {
        switch problem {
        case .microphoneDenied:
            Action(title: "Open System Settings", run: openMicrophoneSettings)
        case .engineFailed, .engineStopped, .engineError, .connectionLost:
            Action(
                title: "Show Log", run: { NSWorkspace.shared.open(EngineServer.logURL) },
                fixes: false)
        case .translationNeedsDownload(let source, let target):
            Action(title: "Download…", run: { download(from: source, to: target) })
        case .transcriptsFolderUnavailable:
            Action(title: "Open Settings…", run: showGeneralSettings)
        default:
            nil
        }
    }

    private func openMicrophoneSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    private func showGeneralSettings() {
        navigation.settingsTab = .general
        dismiss()
        openSettings()
        NSApp.activate()
    }

    private func download(from source: String, to target: String) {
        controller.requestDownload(from: source, to: target)
        dismiss()
        openWindow(id: "main")
        NSApp.activate()
    }
}

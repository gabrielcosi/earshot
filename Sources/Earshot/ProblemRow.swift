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

    /// `.noModel` has none here: the menu's main button sets up models while none is selected.
    private var action: (title: String, run: () -> Void)? {
        switch problem {
        case .microphoneDenied:
            ("Open System Settings", openMicrophoneSettings)
        case .engineFailed, .engineStopped, .engineError, .connectionLost:
            ("Show Log", { NSWorkspace.shared.open(EngineServer.logURL) })
        case .translationNeedsDownload(let source, let target):
            ("Download…", { download(from: source, to: target) })
        case .transcriptsFolderUnavailable:
            ("Open Settings…", showGeneralSettings)
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

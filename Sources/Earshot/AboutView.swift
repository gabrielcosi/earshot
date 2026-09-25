import AppKit
import SwiftUI

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
                .accessibilityHidden(true)
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
    }
}

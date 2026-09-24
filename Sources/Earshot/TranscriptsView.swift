import EarshotKit
import SwiftUI

/// The session being recorded, then every saved transcript, newest first.
struct TranscriptsView: View {
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @State private var files: [URL] = []
    @State private var selection: URL?
    @State private var naming: NamingTarget?

    /// Stands in for the live session in the list selection.
    private static let live = URL(filePath: "/live")

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                if controller.state != .idle || !controller.transcript.utterances.isEmpty {
                    Section("Now") {
                        Label(
                            controller.isRecording ? "Recording" : "Last transcript",
                            systemImage: controller.isRecording ? "record.circle" : "waveform"
                        )
                        .foregroundStyle(controller.isRecording ? .red : .primary)
                        .tag(Self.live)
                    }
                }
                Section("Saved") {
                    ForEach(files, id: \.self) { file in
                        Text(file.deletingPathExtension().lastPathComponent).tag(file)
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            Group {
                if selection == Self.live || (selection == nil && controller.isRecording) {
                    TranscriptView()
                } else if let selection {
                    SavedTranscriptView(file: selection, reload: controller.changedFile) {
                        naming = NamingTarget(file: selection)
                    }
                } else {
                    ContentUnavailableView(
                        "No transcript selected", systemImage: "waveform",
                        description: Text("Start listening from the menu bar."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Transcripts")
        .sheet(item: $naming) { target in NamingView(file: target.file) }
        .onAppear {
            reload()
            takeNamingRequest()
        }
        .onChange(of: navigation.naming) { takeNamingRequest() }
        .onChange(of: controller.savedFile) { reload() }
        .onChange(of: controller.preferences.transcriptsFolder) { reload() }
        .onChange(of: controller.isRecording) {
            if controller.isRecording { selection = Self.live }
        }
    }

    /// A session that just stopped opens selected, with its naming sheet.
    private func takeNamingRequest() {
        guard let file = navigation.naming else { return }
        navigation.naming = nil
        reload()
        selection = file
        naming = NamingTarget(file: file)
    }

    private func reload() {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: controller.preferences.transcriptsFolder, includingPropertiesForKeys: nil))
            ?? []
        files = urls.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

private struct NamingTarget: Identifiable {
    let file: URL
    var id: URL { file }
}

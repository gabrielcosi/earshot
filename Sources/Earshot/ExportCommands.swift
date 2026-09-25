import SwiftUI

extension FocusedValues {
    /// The transcript in the key window, once it can be exported: stored, and not being recorded.
    @Entry var exportableTranscript: UUID?
}

/// File > Export…, where Mac apps keep it, for the transcript on screen.
struct ExportCommands: Commands {
    let controller: SessionController
    @FocusedValue(\.exportableTranscript) private var transcript

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Export…") { if let transcript { Exports.markdown(transcript, controller) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(transcript == nil)
        }
    }
}

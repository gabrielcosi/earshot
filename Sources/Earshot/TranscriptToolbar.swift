import AppKit
import EarshotKit
import SwiftUI

/// The keys the transcript window's view settings are kept under, shared with the View menu.
enum TranscriptSettings {
    static let textSize = "transcriptTextSize"
    static let display = "translationDisplay"
}

/// What can be done with the transcript on screen. The session being recorded is still changing,
/// so it can be copied and shown, but not yet summarized or named.
struct TranscriptToolbar: ToolbarContent {
    let file: URL?
    let isLive: Bool
    let showsTranslation: Bool
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @AppStorage(TranscriptSettings.display) private var display = TranslationDisplay.both

    var body: some ToolbarContent {
        if showsTranslation {
            ToolbarItem {
                Picker("Show", selection: $display) {
                    Text("Original").tag(TranslationDisplay.original)
                    Text("Original + Translation").tag(TranslationDisplay.both)
                    Text("Translation").tag(TranslationDisplay.translation)
                }
                .pickerStyle(.segmented)
                .help("Show the original, the translation, or both (⌘1, ⌘2, ⌘3)")
            }
        }
        ToolbarItemGroup {
            Button("Copy", systemImage: "doc.on.doc", action: copy)
                .help("Copy the transcript as Markdown")
                .disabled(file == nil)
            Button("Show in Finder", systemImage: "folder") {
                if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            .help("Show the transcript's file in Finder")
            .disabled(file == nil)
            if summarizing {
                ProgressView().controlSize(.small).help("Summarizing…")
            }
            Button("Summarize", systemImage: "text.badge.star") {
                if let file { Task { await controller.summarize(file) } }
            }
            .help("Write an overview, decisions, and action items above the transcript")
            .disabled(file == nil || busy || summarizing)
            Button("Name Speakers…", systemImage: "person.2") { navigation.naming = file }
                .help("Name the speakers")
                .disabled(file == nil || busy)
        }
    }

    private var busy: Bool { isLive && controller.state != .idle }

    private var summarizing: Bool {
        file.map(controller.summarizing.contains) ?? false
    }

    private func copy() {
        guard let file, let markdown = try? String(contentsOf: file, encoding: .utf8) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}

/// A summary of the transcript on screen failed: said where the transcript is, with the retry.
struct SummaryFailureBanner: View {
    let file: URL
    let failure: Problem
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(failure.message())
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Summary Settings…") {
                navigation.settingsTab = .summaries
                openSettings()
            }
            Button("Try Again") { Task { await controller.summarize(file) } }
            Button("Dismiss", systemImage: "xmark") { controller.dismissSummaryFailure(file) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.bar, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }
}

import AppKit
import EarshotKit
import SwiftUI
import UniformTypeIdentifiers

/// The keys the transcript window's view settings are kept under, shared with the View menu.
enum TranscriptSettings {
    static let textSize = "transcriptTextSize"
    static let display = "translationDisplay"
}

extension TranslationDisplay {
    /// The same in the toolbar, the View menu, and the captions overlay.
    var title: String {
        switch self {
        case .original: "Original"
        case .both: "Original + Translation"
        case .translation: "Translation"
        }
    }
}

/// What can be done with the transcript on screen. The session being recorded is still changing,
/// so it can be copied and shown, but not yet summarized or named.
struct TranscriptToolbar: ToolbarContent {
    /// Nil until the live session's first line is stored.
    let transcript: UUID?
    let isLive: Bool
    /// The session has ended in the store; only then can its speakers be named.
    let sealed: Bool
    /// The kept audio, when there is some.
    let audio: URL?
    let showsTranslation: Bool
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @AppStorage(TranscriptSettings.display) private var display = TranslationDisplay.both

    var body: some ToolbarContent {
        @Bindable var navigation = navigation
        if showsTranslation {
            ToolbarItem {
                Picker("Show", selection: $display) {
                    ForEach(TranslationDisplay.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Show the original, the translation, or both (⌘1, ⌘2, ⌘3)")
            }
        }
        ToolbarItemGroup {
            Button("Copy", systemImage: "doc.on.doc", action: copy)
                .help("Copy the transcript as Markdown")
                .disabled(transcript == nil)
            Menu {
                Button("Show Markdown File in Finder", action: showFile)
                    .disabled(file == nil)
                Button("Show Audio in Finder") {
                    if let audio { NSWorkspace.shared.activateFileViewerSelecting([audio]) }
                }
                .disabled(audio == nil)
                Divider()
                Button("Export…") { if let transcript { Exports.markdown(transcript, controller) } }
                    .disabled(transcript == nil || busy)
                Button("Export Audio…") {
                    if let transcript, let audio { Exports.audio(transcript, audio, controller) }
                }
                .disabled(audio == nil)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            } primaryAction: {
                showFile()
            }
            .help("Show the transcript's Markdown file, or the transcripts folder, in Finder")
            if summarizing {
                ProgressView().controlSize(.small).help("Summarizing…")
            }
            Button("Summarize", systemImage: "text.badge.star") {
                if let transcript { Task { await controller.summarize(transcript) } }
            }
            .help("Write an overview, decisions, and action items above the transcript")
            .disabled(transcript == nil || busy || summarizing)
            Toggle("Name Speakers", systemImage: "person.2", isOn: $navigation.showsSpeakers)
                .help("Show or hide the speakers, to name them")
                .disabled(!navigation.showsSpeakers && !sealed)
        }
    }

    private var busy: Bool { isLive && controller.state != .idle }

    private var summarizing: Bool {
        transcript.map(controller.summarizing.contains) ?? false
    }

    /// The Markdown file, while it is where Earshot wrote it.
    private var file: URL? {
        switch transcript.flatMap({ controller.exports[$0] }) {
        case .current(let file), .edited(let file): file
        default: nil
        }
    }

    /// With no file to show, the transcripts folder, where the file is written.
    private func showFile() {
        NSWorkspace.shared.activateFileViewerSelecting([
            file ?? controller.preferences.transcriptsFolder
        ])
    }

    private func copy() {
        guard let transcript, let view = try? controller.store.view(transcript) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(view.markdown(rules: controller.rules), forType: .string)
    }
}

/// Export… and Export Audio…, in the standard save panel, as a sheet on the key window.
enum Exports {
    /// Suggests the file Earshot keeps up to date while it is current, and otherwise a name no
    /// file has yet, so Return never replaces an edited copy or another session's file.
    static func markdown(_ transcript: UUID, _ controller: SessionController) {
        guard let view = try? controller.store.view(transcript) else { return }
        let folder = controller.preferences.transcriptsFolder
        controller.checkExport(transcript)
        let file: URL =
            if case .current(let current) = controller.exports[transcript] {
                current
            } else {
                TranscriptExporter.freeFile(
                    named: MarkdownExport.filename(for: view.startedAt), in: folder)
            }
        choose(file, type: UTType(filenameExtension: "md") ?? .plainText) { chosen in
            controller.saveCopy(transcript, to: chosen)
        }
    }

    static func audio(_ transcript: UUID, _ audio: URL, _ controller: SessionController) {
        guard let view = try? controller.store.view(transcript) else { return }
        let name = (MarkdownExport.filename(for: view.startedAt) as NSString)
            .deletingPathExtension
        let file = TranscriptExporter.freeFile(
            named: name + ".m4a", in: controller.preferences.transcriptsFolder)
        choose(file, type: .mpeg4Audio) { chosen in
            Task { await controller.saveAudio(audio, to: chosen) }
        }
    }

    /// The panel asks before replacing a file.
    private static func choose(_ file: URL, type: UTType, then save: @escaping (URL) -> Void) {
        guard let window = NSApp.keyWindow else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        panel.allowedContentTypes = [type]
        panel.directoryURL = file.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let chosen = panel.url { save(chosen) }
        }
    }
}

/// The Markdown file no longer matches what Earshot wrote: it was changed, moved, or deleted
/// outside Earshot, or it is an 0.1 file Earshot would write differently. Said where the
/// transcript is, with a way to write a new one.
struct StaleExportBanner: View {
    let transcript: UUID
    let file: URL
    let missing: Bool
    @Environment(SessionController.self) private var controller

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.ellipsis")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(
                missing
                    ? "The Markdown file was moved or deleted, so Earshot no longer updates it."
                    : "The Markdown file no longer matches what Earshot wrote, so Earshot no longer updates it."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            if !missing {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            Button("Export…") { Exports.markdown(transcript, controller) }
        }
        .padding(10)
        .background(.bar, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }
}

/// A summary of the transcript on screen failed: said where the transcript is, with the retry.
struct SummaryFailureBanner: View {
    let transcript: UUID
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
            Button("Try Again") { Task { await controller.summarize(transcript) } }
            Button("Dismiss", systemImage: "xmark") { controller.dismissSummaryFailure(transcript) }
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

import EarshotCapture
import EarshotKit
import SwiftUI

/// A saved transcript: its summary when it has one, then every line, playable when its
/// audio was kept.
struct SavedTranscriptView: View {
    let file: URL
    /// Changes when a transcript is renamed or summarized, so the file is read again.
    let reload: URL?
    let name: () -> Void
    @State private var player = ClipPlayer()
    @Environment(SessionController.self) private var controller

    /// A line plays until the next one starts; a long monologue plays its first minute, and its
    /// text is right there for the rest.
    private static let longestClip = 60.0

    var body: some View {
        let document = TranscriptDocument(
            markdown: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
        let audio = TranscriptAudio.file(for: file)
        let hasAudio = FileManager.default.fileExists(atPath: audio.path(percentEncoded: false))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(document.title).font(.title2.bold())
                if let summary = document.summary {
                    SummaryView(summary: summary)
                    Divider()
                }
                ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                    row(line) {
                        let next = document.lines.dropFirst(index + 1).first?.start
                        let seconds = min(
                            (next ?? line.start + Self.longestClip) - line.start, Self.longestClip)
                        player.toggle(
                            line.id, file: audio, from: line.start, seconds: max(seconds, 1))
                    }
                    .environment(\.hasAudio, hasAudio)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .id(reload)
        .onDisappear { player.stop() }
        .toolbar {
            if controller.summarizing.contains(file) {
                ProgressView().controlSize(.small)
            } else {
                Button(
                    document.summary == nil ? "Summarize" : "Summarize Again",
                    systemImage: "text.badge.star"
                ) { Task { await controller.summarize(file) } }
            }
            Button("Name Speakers…", systemImage: "person.2", action: name)
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        }
    }

    private func row(_ line: TranscriptDocument.Line, play: @escaping () -> Void) -> some View {
        LineRow(line: line, playing: player.playing == line.id, play: play)
    }
}

private struct LineRow: View {
    let line: TranscriptDocument.Line
    let playing: Bool
    let play: () -> Void
    @Environment(\.hasAudio) private var hasAudio

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if hasAudio {
                Button(
                    playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill",
                    action: play
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.label).font(.headline)
                    Text(MarkdownExport.timestamp(line.start))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(line.text)
                if let translation = line.translation {
                    Label(translation, systemImage: "translate").foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SummaryView: View {
    let summary: TranscriptDocument.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "text.badge.star").font(.headline)
            Text(
                (try? AttributedString(
                    markdown: summary.text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(summary.text))
            Text("Written by \(summary.model). Check it against the transcript.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

private struct HasAudioKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var hasAudio: Bool {
        get { self[HasAudioKey.self] }
        set { self[HasAudioKey.self] = newValue }
    }
}

import EarshotKit
import SwiftUI
@preconcurrency import Translation

struct TranscriptView: View {
    @Environment(SessionController.self) private var controller

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let summary = controller.summary {
                        SummaryView(summary: summary)
                    }
                    ForEach(controller.transcript.rows) { row in
                        view(row)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
                .textSelection(.enabled)
            }
            .onChange(of: controller.transcript) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .overlay {
            if controller.transcript.rows.isEmpty {
                ContentUnavailableView(
                    controller.isRecording ? "Listening…" : "Nothing transcribed yet",
                    systemImage: "waveform",
                    description: Text("Start listening from the menu bar.")
                )
            }
        }
        .translationTask(controller.downloadRequest) { session in
            try? await session.prepareTranslation()
            controller.downloadFinished()
        }
    }

    private func view(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(controller.displayName(row.speaker))
                    .font(.headline)
                    .foregroundStyle(color(row.speaker))
                Text(MarkdownExport.timestamp(row.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(paragraph(row))
            if row.translation != nil || row.pendingTranslation != nil {
                Label {
                    Text(translation(row))
                } icon: {
                    Image(systemName: "translate")
                }
                .foregroundStyle(.secondary)
                .labelStyle(TranslationLabelStyle())
            }
        }
    }

    /// The paragraph's translation, then the live translation of the words still arriving.
    private func translation(_ row: Row) -> AttributedString {
        var text = AttributedString(row.translation ?? "")
        if let pending = row.pendingTranslation {
            var tail = AttributedString(row.translation == nil ? pending : " " + pending)
            tail.foregroundColor = .gray
            text += tail
        }
        return text
    }

    /// Final text in the primary style, then the words still being recognized in grey.
    private func paragraph(_ row: Row) -> AttributedString {
        let rules = controller.rules
        let final = rules.apply(row.text)
        var text = AttributedString(final)
        if let pending = row.pending.map(rules.apply), !pending.isEmpty {
            var tail = AttributedString(final.isEmpty ? pending : " " + pending)
            tail.foregroundColor = .secondary
            text += tail
        }
        return text
    }

    private func color(_ speaker: Speaker) -> Color {
        let palette: [Color] = [
            .gray, .blue, .orange, .purple, .green, .pink, .teal, .brown, .indigo,
        ]
        switch speaker {
        case .me: return .primary
        case .remote(let slot): return palette[slot % palette.count]
        case .unknown: return .secondary
        }
    }
}

private struct TranslationLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.caption)
            configuration.title
        }
    }
}

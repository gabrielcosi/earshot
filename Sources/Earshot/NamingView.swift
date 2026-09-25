import EarshotKit
import SwiftUI

/// Names the remote speakers of a stored transcript, from a few of their lines and, when enabled,
/// suggestions from what the transcript itself says.
struct NamingView: View {
    let transcript: UUID
    @Environment(SessionController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var stored: StoredTranscript?
    @State private var speakers: [SpeakerNames.Speaker] = []
    @State private var names: [Speaker: String] = [:]
    @State private var suggestions: [Speaker: SpeakerSuggester.Suggestion] = [:]
    @State private var suggesting = false
    @State private var player = ClipPlayer()

    private var savedAudio: URL? { controller.keptAudio(stored) }

    /// Kept audio, or the recording of the session that just ended.
    private var hasAudio: Bool {
        savedAudio != nil || (transcript == controller.savedID && controller.lastRecording != nil)
    }

    private var title: String {
        stored.map { $0.title ?? MarkdownExport.title(for: $0.startedAt) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name the Speakers").font(.title2.bold())
                    Text(title).foregroundStyle(.secondary)
                }
                Spacer()
                if suggesting {
                    ProgressView().controlSize(.small)
                    Text("Looking for names…").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()

            Form {
                if speakers.isEmpty {
                    Text("This transcript has no other speakers.").foregroundStyle(.secondary)
                }
                ForEach(speakers) { speaker in
                    Section(speaker.label) {
                        ForEach(speaker.samples, id: \.self) { sample in
                            HStack(alignment: .firstTextBaseline) {
                                if hasAudio {
                                    let playing = player.playing == "\(sample.start)"
                                    Button(
                                        playing ? "Stop" : "Play",
                                        systemImage: playing ? "stop.fill" : "play.fill"
                                    ) { toggle(sample) }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                }
                                Text("“\(sample.text)”").foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        TextField(
                            "Name", text: binding(for: speaker.speaker), prompt: Text(speaker.label)
                        )
                        if let suggestion = suggestions[speaker.speaker] {
                            Text("Suggested from “\(suggestion.evidence)”")
                                .font(.caption).foregroundStyle(.tint)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Skip") { dismiss() }
                Button("Save Names", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 560)
        .task { await load() }
        .onDisappear {
            player.stop()
            if transcript == controller.savedID {
                controller.discardLastRecording()
                controller.sessionFinished()
            }
        }
    }

    private func binding(for speaker: Speaker) -> Binding<String> {
        Binding(get: { names[speaker] ?? "" }, set: { names[speaker] = $0 })
    }

    private func load() async {
        guard let stored = try? controller.store.view(transcript) else { return }
        self.stored = stored
        speakers = stored.speakersToName()
        guard controller.preferences.suggestSpeakerNames, !speakers.isEmpty else { return }
        suggesting = true
        let markdown = stored.markdown(rules: controller.rules)
        let found = await SpeakerSuggester.suggest(for: markdown, labels: speakers.map(\.label))
        suggesting = false
        for speaker in speakers {
            guard let suggestion = found[speaker.label] else { continue }
            suggestions[speaker.speaker] = SpeakerSuggester.Suggestion(
                name: suggestion.name,
                evidence: SpeakerNames.evidence(for: suggestion.name, in: markdown)
                    ?? suggestion.evidence)
            if (names[speaker.speaker] ?? "").isEmpty { names[speaker.speaker] = suggestion.name }
        }
    }

    /// Eight seconds is enough to recognise a voice and short enough to go through several
    /// speakers quickly; the clip stops early rather than run into the next line's speaker.
    private func toggle(_ sample: SpeakerNames.Sample) {
        let id = "\(sample.start)"
        let seconds = min(8, sample.end.map { $0 - sample.start } ?? 8)
        if let savedAudio {
            player.toggle(id, file: savedAudio, from: sample.start, seconds: seconds)
        } else {
            player.toggle(id, clip: controller.clip(at: sample.start, seconds: seconds))
        }
    }

    private func save() {
        controller.name(speakers: names, in: transcript)
        dismiss()
    }
}

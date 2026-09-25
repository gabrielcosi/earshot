import EarshotKit
import SwiftUI

/// The transcript's speakers beside it, to name them: each with how long they talk, a few of
/// their lines to hear, and, when enabled, a name the transcript itself says. A valid name is
/// stored with Return, when its field loses focus, and when the panel closes or another
/// transcript opens; Escape puts a field back as it was.
struct SpeakersPanel: View {
    let transcript: UUID?
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.undoManager) private var undoManager
    @State private var stored: StoredTranscript?
    @State private var unreadable = false
    /// What is typed in each field and not stored yet.
    @State private var drafts: [Speaker: String] = [:]
    @State private var suggestions: [Speaker: SpeakerSuggester.Suggestion] = [:]
    @State private var suggesting = false
    @State private var suggested = false
    @State private var player = ClipPlayer()
    @FocusState private var focus: Speaker?

    private var sealed: Bool { stored?.endedAt != nil }

    var body: some View {
        content
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if sealed { footer }
            }
            .task { await follow() }
            .task(id: sealed) { if sealed { await suggest() } }
            .onChange(of: focus) { left, _ in
                if left != nil { save() }
            }
            // Done and Name Speakers close the panel. Whether SwiftUI keeps a closed inspector's
            // content alive is not documented, so closing does not rely on onDisappear.
            .onChange(of: navigation.showsSpeakers) { _, shows in
                if !shows { close() }
            }
            .onDisappear(perform: close)
    }

    /// The panel closes, or another transcript opens: what is typed and valid is stored, and
    /// naming this transcript is done. Undo is for the transcript on screen, so names stored as
    /// another one opens are not undone from it.
    private func close() {
        player.stop()
        let shown = navigation.selection?.transcript(live: controller.savedID)
        save(undoable: shown == transcript)
        drafts = [:]
        if let transcript { controller.finishNaming(transcript) }
    }

    @ViewBuilder private var content: some View {
        if let stored, sealed {
            form(stored)
        } else if stored != nil || (transcript == nil && controller.state != .idle) {
            ContentUnavailableView(
                "Speakers are named once the session ends", systemImage: "person.2")
        } else if unreadable {
            ContentUnavailableView(
                "Can’t read this transcript", systemImage: "exclamationmark.triangle")
        } else if transcript == nil {
            ContentUnavailableView("No transcript selected", systemImage: "person.2")
        } else {
            // Every state must draw something: the panel's tasks start only once a view appears,
            // and an empty branch never appears, so the transcript would never be read.
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func form(_ stored: StoredTranscript) -> some View {
        let samples = Dictionary(
            uniqueKeysWithValues: stored.speakersToName().map { ($0.speaker, $0.samples) })
        let marks = Self.marks(in: stored)
        return Form {
            if suggesting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Looking for names…").foregroundStyle(.secondary)
                }
            }
            ForEach(stored.speakers, id: \.self) { speaker in
                Section {
                    switch speaker {
                    case .me:
                        Text("Your microphone. It’s always “Me”.").foregroundStyle(.secondary)
                    case .unknown:
                        Text("Speech Earshot couldn’t give to one speaker.")
                            .foregroundStyle(.secondary)
                    case .remote:
                        nameField(speaker, in: stored)
                        ForEach(samples[speaker] ?? [], id: \.self, content: sample)
                    }
                } header: {
                    header(speaker, mark: marks[speaker], in: stored)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func header(_ speaker: Speaker, mark: TranscriptLine?, in stored: StoredTranscript)
        -> some View
    {
        let talk = stored.talkTime(of: speaker)
        return HStack {
            SpeakerName(
                name: stored.label(speaker), badge: mark?.badge ?? "?",
                colour: (mark?.voice ?? .unknown).colour)
            Spacer()
            if talk > 0 {
                Text(
                    Duration.seconds(talk).formatted(
                        .units(
                            allowed: [.hours, .minutes, .seconds], width: .abbreviated,
                            maximumUnitCount: 1))
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func nameField(_ speaker: Speaker, in stored: StoredTranscript) -> some View {
        let invalid: SpeakerNames.InvalidName? =
            if case .failure(let invalid) = typedNames[speaker] { invalid } else { nil }
        TextField("Name", text: draft(speaker), prompt: Text(speaker.label))
            .focused($focus, equals: speaker)
            .onSubmit {
                save()
                if case .failure = typedNames[speaker] { return }
                focus = nil
            }
            .onExitCommand { drafts[speaker] = nil }
            .overlay {
                if invalid != nil {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(.red)
                }
            }
            .accessibilityHint(invalid?.message ?? "")
        if let invalid {
            Text(invalid.message).font(.caption).foregroundStyle(.red)
        } else if stored.names[speaker] == nil {
            if let suggestion = suggestions[speaker] {
                HStack(alignment: .firstTextBaseline) {
                    Text("Suggested: \(Text(suggestion.name).bold())")
                    Spacer()
                    Button("Use") {
                        drafts[speaker] = suggestion.name
                        focus = speaker
                    }
                    .help("Put this name in the field")
                }
                Text("“\(suggestion.evidence)”")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if suggested {
                Text("No name found in the transcript.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sample(_ sample: SpeakerNames.Sample) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if hasAudio {
                let playing = player.playing == "\(sample.start)"
                Button(
                    playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill"
                ) { toggle(sample) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityLabel(playing ? "Stop" : "Play this line")
            }
            Text("“\(sample.text)”").foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var footer: some View {
        HStack {
            Text("Undo (⌘Z) reverts a rename").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Done") { navigation.showsSpeakers = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    /// Each speaker's first line, which has their badge and colour as the transcript shows them.
    private static func marks(in stored: StoredTranscript) -> [Speaker: TranscriptLine] {
        var marks: [Speaker: TranscriptLine] = [:]
        for (paragraph, line) in zip(stored.paragraphs, TranscriptLine.lines(in: stored))
        where marks[paragraph.speaker] == nil {
            marks[paragraph.speaker] = line
        }
        return marks
    }

    // MARK: - Names

    private func draft(_ speaker: Speaker) -> Binding<String> {
        Binding(
            get: { drafts[speaker] ?? stored?.names[speaker] ?? "" },
            set: { drafts[speaker] = $0 })
    }

    /// What is typed, checked together as it would be stored: each name against the stored
    /// names and every other name typed that is valid, so what the fields say is what is stored.
    /// Names typed as they are stored are left out.
    private var typedNames: [Speaker: Result<String?, SpeakerNames.InvalidName>] {
        guard let stored else { return [:] }
        var failed: [Speaker: SpeakerNames.InvalidName] = [:]
        var names: [Speaker: String]
        // A name that fails can free another's, so failures are found until none is new.
        repeat {
            names = stored.names
            for (speaker, draft) in drafts where failed[speaker] == nil {
                let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                names[speaker] = name.isEmpty ? nil : name
            }
            let before = failed.count
            for (speaker, draft) in drafts where failed[speaker] == nil {
                do throws(SpeakerNames.InvalidName) {
                    _ = try SpeakerNames.validate(draft, for: speaker, names: names)
                } catch {
                    failed[speaker] = error
                }
            }
            if failed.count == before { break }
        } while true
        var typed: [Speaker: Result<String?, SpeakerNames.InvalidName>] = [:]
        for speaker in drafts.keys {
            if let error = failed[speaker] {
                typed[speaker] = .failure(error)
            } else if names[speaker] != stored.names[speaker] {
                typed[speaker] = .success(names[speaker])
            }
        }
        return typed
    }

    /// Stores every valid name typed, as one change; an invalid one stays in its field, with why.
    /// Stored names leave the drafts at once: the store's copy may merge a rename and a quick
    /// Undo into no change, and a draft left behind would be saved again later.
    private func save(undoable: Bool = true) {
        guard let transcript, sealed else { return }
        var changes: [Speaker: String?] = [:]
        for case (let speaker, .success(let name)) in typedNames {
            changes.updateValue(name, forKey: speaker)
        }
        guard !changes.isEmpty,
            controller.setNames(
                changes, in: transcript, undoManager: undoable ? undoManager : nil)
        else { return }
        for speaker in changes.keys { drafts[speaker] = nil }
    }

    // MARK: - Loading

    /// Follows the transcript in the store, so a name shows as soon as it is stored, and again
    /// after Undo.
    private func follow() async {
        guard let transcript else { return }
        do {
            for try await view in controller.store.viewChanges(transcript) {
                stored = view
                unreadable = view == nil
                // What is typed and now stored, or undone back to, is nothing new.
                let typed = typedNames
                drafts = drafts.filter { typed[$0.key] != nil }
            }
        } catch {
            stored = nil
            unreadable = true
        }
    }

    private func suggest() async {
        guard controller.preferences.suggestSpeakerNames, let stored else { return }
        let speakers = stored.speakersToName()
        guard !speakers.isEmpty else { return }
        suggesting = true
        defer { suggesting = false }
        let found = await SpeakerSuggester.suggest(
            for: stored.markdown(rules: controller.rules), labels: speakers.map(\.label))
        guard let found else { return }
        suggested = true
        for speaker in speakers {
            suggestions[speaker.speaker] = found[speaker.label]
        }
    }

    // MARK: - Hearing a speaker

    private var savedAudio: URL? { controller.keptAudio(stored) }

    /// Kept audio, or the recording of the session that just ended.
    private var hasAudio: Bool {
        savedAudio != nil || (transcript == controller.savedID && controller.lastRecording != nil)
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
}

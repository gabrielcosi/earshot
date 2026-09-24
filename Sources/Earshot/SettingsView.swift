import EarshotCapture
import EarshotKit
import SwiftUI

struct SettingsView: View {
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @State private var inputs: [AudioDevices.Input] = []

    var body: some View {
        @Bindable var controller = controller
        @Bindable var navigation = navigation
        @Bindable var library = controller.library
        @Bindable var preferences = controller.preferences
        Form {
            Section("Models") {
                modelRow(
                    title: "Transcription", repo: library.transcription,
                    missing: "No transcription model downloaded")
                modelRow(
                    title: "Speaker detection", repo: library.diarization,
                    missing: "Not downloaded: transcripts will have no speaker labels")
                HStack {
                    Spacer()
                    Button("Browse Models…") { navigation.browsingModels = true }
                }
            }

            Section {
                Toggle("Include my microphone", isOn: $preferences.useMicrophone)
                    .disabled(controller.state != .idle)
                Picker("Input device", selection: $preferences.microphone) {
                    Text("System default").tag(String?.none)
                    ForEach(inputs) { input in
                        Text(input.name).tag(Optional(input.uid))
                    }
                }
                Toggle(isOn: $preferences.cancelSpeakerEcho) {
                    Text("Cancel speaker echo")
                    Text(
                        "For listening on speakers: removes what the Mac plays from your microphone, so it is not transcribed twice. Headphones are recommended; with them, leave this off."
                    )
                }
                .disabled(!preferences.useMicrophone || controller.state != .idle)
            } header: {
                Text("Microphone")
            } footer: {
                Text(
                    "Used for your own voice. Everyone else is captured from the Mac's audio output. Turn it off to transcribe a podcast or video on its own."
                )
            }

            Section {
                Toggle(isOn: $preferences.keepAudio) {
                    Text("Keep audio")
                    Text(
                        "Saves the microphone and what the Mac plays next to each transcript (about 23 MB an hour), so every line can be played back."
                    )
                }
                LabeledContent("Folder") {
                    Text(preferences.transcriptsFolder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if !preferences.usesDefaultTranscriptsFolder {
                        Button("Use Default") { preferences.resetTranscriptsFolder() }
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            preferences.transcriptsFolder
                        ])
                    }
                    Button("Choose…", action: chooseTranscriptsFolder)
                }
            } header: {
                Text("Transcripts")
            } footer: {
                Text("Each transcript is saved as Markdown after every finished line.")
            }

            Section {
                LabeledContent("Spoken languages") { SpokenLanguagesMenu().fixedSize() }
                Toggle("Translate into my language", isOn: $controller.translationEnabled)
                Picker("My language", selection: $controller.primaryLanguage) {
                    ForEach(primaryChoices, id: \.self) { code in
                        Text(Languages.displayName(code)).tag(code)
                    }
                }
                .disabled(!controller.translationEnabled)
            } header: {
                Text("Languages")
            } footer: {
                Text(
                    "Transcripts stay in the languages you pick. With one, it is used throughout; with several, each line is checked and redone when it strays. Pick none to allow any language."
                )
            }

            SummarySettings()

            Section("General") {
                Toggle("Open at login", isOn: $preferences.openAtLogin)
                Toggle("Show Dock icon", isOn: $preferences.showDockIcon)
                Toggle("Keep the Mac awake while recording", isOn: $preferences.keepAwake)
                Toggle(isOn: $preferences.suggestSpeakerNames) {
                    Text("Suggest speaker names")
                    Text(
                        SpeakerSuggester.isAvailable
                            ? "When you name speakers, Apple's on-device model reads the transcript for introductions like “I'm John Doe”. Nothing leaves this Mac."
                            : "Needs Apple Intelligence, which is off or unavailable on this Mac."
                    )
                }
                .disabled(!SpeakerSuggester.isAvailable)
                Toggle(isOn: $preferences.keepEngineLoaded) {
                    Text("Keep engine loaded")
                    Text(
                        "Starts instantly, using about 1 GB of memory while idle. Off, the engine loads when you open the menu or start, and your first seconds are buffered meanwhile."
                    )
                }
                .onChange(of: preferences.keepEngineLoaded) {
                    if preferences.keepEngineLoaded {
                        controller.prewarm()
                    } else {
                        controller.scheduleUnload()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $navigation.browsingModels) { ModelLibraryView() }
        .onAppear { inputs = AudioDevices.inputs() }
    }

    private func chooseTranscriptsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        try? controller.preferences.setTranscriptsFolder(folder)
    }

    private var primaryChoices: [String] {
        let codes = Set(controller.translationLanguages.map(\.minimalIdentifier))
            .union([controller.primaryLanguage])
        return codes.sorted { Languages.displayName($0) < Languages.displayName($1) }
    }

    private func modelRow(title: String, repo: String, missing: String) -> some View {
        let library = controller.library
        let model = library.catalog.model(repo: repo)
        return LabeledContent(title) {
            if let model, library.installed.contains(repo) {
                VStack(alignment: .trailing) {
                    Text(ModelInfo.of(model).name)
                    if library.isOutdated(repo) {
                        Text("Update available in Browse Models").font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(ModelInfo.of(model).detail).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(missing).foregroundStyle(.orange)
            }
        }
    }
}

/// How the library presents each model.
struct ModelInfo {
    let name: String
    let detail: String
    let recommended: Bool

    static func of(_ model: SpeechModel) -> ModelInfo {
        switch model.repo {
        case "nvidia/nemotron-3.5-asr-streaming-0.6b":
            ModelInfo(
                name: "Nemotron 3.5 Streaming", detail: "Multilingual, detects the language",
                recommended: true)
        case "nvidia/nemotron-speech-streaming-en-0.6b":
            ModelInfo(name: "Nemotron Speech Streaming", detail: "English only", recommended: false)
        case "nvidia/Nemotron-3-Diarization":
            ModelInfo(name: "Nemotron 3 Diarization", detail: "Up to 8 speakers", recommended: true)
        case "nvidia/diar_streaming_sortformer_4spk-v2":
            ModelInfo(
                name: "Streaming Sortformer v2", detail: "Up to 4 speakers", recommended: false)
        default:
            ModelInfo(name: model.repo, detail: "", recommended: false)
        }
    }
}

struct ModelLibraryView: View {
    @Environment(SessionController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let library = controller.library
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Library").font(.title2.bold())
                    Text("Download models and choose which ones Earshot uses.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            Form {
                Section("Transcription") {
                    ForEach(library.catalog.models(for: .transcription)) { row($0) }
                }
                Section("Speaker detection") {
                    ForEach(library.catalog.models(for: .diarization)) { row($0) }
                }
                if let error = library.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Label(
                "Models are stored and run on this Mac.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
        }
        .frame(width: 620, height: 520)
    }

    private func row(_ model: SpeechModel) -> some View {
        let library = controller.library
        let info = ModelInfo.of(model)
        let installed = library.installed.contains(model.repo)
        let selected =
            model.kind == .transcription
            ? library.transcription == model.repo : library.diarization == model.repo
        return HStack(spacing: 12) {
            Image(systemName: selected && installed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected && installed ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(info.name).font(.headline)
                    if info.recommended {
                        Text("Recommended").font(.caption).foregroundStyle(.tint)
                    }
                }
                Text(info.detail).font(.callout).foregroundStyle(.secondary)
                if let license = model.license {
                    Text(license).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(model.size.formatted(.byteCount(style: .file)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let progress = library.progress[model.repo] {
                ProgressView(value: progress).frame(width: 90)
                Button("Cancel") { library.cancel(model) }
            } else if !installed {
                Button("Download") { library.download(model) }
            } else if library.isOutdated(model.repo) {
                Button("Update") { library.download(model) }
            } else if !selected {
                Button("Use") { select(model) }
                    .disabled(controller.state != .idle)
            } else {
                Text("In use").foregroundStyle(.tint)
            }
            if installed, !selected {
                Menu {
                    Button("Delete", role: .destructive) { library.delete(model) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    private func select(_ model: SpeechModel) {
        switch model.kind {
        case .transcription: controller.library.transcription = model.repo
        case .diarization: controller.library.diarization = model.repo
        }
    }
}

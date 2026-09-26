import EarshotCapture
import EarshotKit
import SwiftUI

/// The Settings window: a tab per area, opened with ⌘, or by whatever needs one of them.
struct SettingsWindow: View {
    @Environment(Navigation.self) private var navigation
    @Environment(SessionController.self) private var controller

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.settingsTab) {
            Tab("General", systemImage: "gearshape", value: .general) { GeneralSettings() }
            Tab("Words", systemImage: "character.book.closed", value: .words) { WordsView() }
            Tab("Microphone", systemImage: "mic", value: .microphone) { MicrophoneSettings() }
            Tab("Models", systemImage: "square.stack.3d.down.right", value: .models) {
                ModelSettings()
            }
            Tab("Summaries", systemImage: "text.badge.star", value: .summaries) {
                Form { SummarySettings() }.formStyle(.grouped)
            }
            Tab("About", systemImage: "info.circle", value: .about) { AboutView() }
        }
        .frame(width: 620, height: 560)
        .onAppear { controller.preferences.openWindows += 1 }
        .onDisappear { controller.preferences.openWindows -= 1 }
    }
}

struct GeneralSettings: View {
    @Environment(SessionController.self) private var controller
    @AppStorage(CaptionsSettings.textSize) private var captionSize = CaptionTextSize.medium

    /// Low was measured on a real session. Medium and High were measured on the test fixtures,
    /// both sides speaking: 36 and 43 MB an hour, against Low's 27 on the same audio, and 25 and
    /// 32 with the microphone off. The fixtures have nothing above 8 kHz, which Medium and High
    /// keep, so real audio comes out a little larger; both sides speaking without a pause, it
    /// measured 47 and 62.
    private static func megabytesPerHour(_ quality: AudioQuality) -> Int {
        switch quality {
        case .low: 23
        case .medium: 35
        case .high: 45
        }
    }

    var body: some View {
        @Bindable var controller = controller
        @Bindable var preferences = controller.preferences
        Form {
            Section {
                Toggle(isOn: $preferences.keepAudio) {
                    Text("Keep audio")
                    Text(
                        "Keeps a recording of your microphone and the Mac's sound with each transcript (about \(Self.megabytesPerHour(preferences.keepAudioQuality)) MB an hour), so every line can be played back."
                    )
                }
                Picker(selection: $preferences.keepAudioQuality) {
                    Text("Low").tag(AudioQuality.low)
                    Text("Medium").tag(AudioQuality.medium)
                    Text("High").tag(AudioQuality.high)
                } label: {
                    Text("Audio Quality")
                    // High records both sides again at 48 kHz PCM16, 346 MB an hour each.
                    Text(
                        preferences.keepAudioQuality == .high
                            ? "Applies from the next session. With Cancel speaker echo on, your microphone is kept as the engine hears it. High uses up to 0.7 GB more disk space an hour while recording, freed when the session ends."
                            : "Applies from the next session. With Cancel speaker echo on, your microphone is kept as the engine hears it."
                    )
                }
                .disabled(!preferences.keepAudio)
                LabeledContent {
                    Text(
                        preferences.lostTranscriptsFolder
                            ?? preferences.transcriptsFolder.path(percentEncoded: false)
                    )
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                } label: {
                    Text("Folder")
                    if preferences.transcriptsFolderLost {
                        Text(
                            "Earshot could not open the folder you chose. Choose it again, or use the default."
                        )
                    }
                }
                HStack {
                    Spacer()
                    if !preferences.usesDefaultTranscriptsFolder
                        || preferences.transcriptsFolderLost
                    {
                        Button("Use Default") {
                            preferences.resetTranscriptsFolder()
                            Task { await controller.importEarlierTranscripts() }
                        }
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
                Text(
                    "Earshot saves each transcript after every finished line and writes a Markdown copy here when the session ends. It keeps the copy up to date until the copy is changed, moved, or deleted outside Earshot."
                )
            }

            if !controller.unimportedFiles.isEmpty {
                Section {
                    ForEach(controller.unimportedFiles, id: \.self) { file in
                        LabeledContent(file.lastPathComponent) {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([file])
                            }
                        }
                    }
                } header: {
                    Text("Not Imported")
                } footer: {
                    Text(
                        "Earshot 0.1 saved these files, but Earshot could not read them as transcripts, so they are not in the window. The files are left as they are."
                    )
                }
            }

            Section {
                LabeledContent("Spoken languages") { SpokenLanguagesMenu().fixedSize() }
                Toggle("Translate into my language", isOn: $controller.translationEnabled)
                Picker(selection: $controller.primaryLanguage) {
                    ForEach(controller.translationChoices, id: \.self) { code in
                        Text(Languages.displayName(code)).tag(code)
                    }
                } label: {
                    Text("My language")
                    Text("Used for translations and summaries.")
                }
            } header: {
                Text("Languages")
            } footer: {
                Text(
                    "Transcripts stay in the languages you pick. With one, it is used throughout; with several, each line is checked and redone when it strays. Pick none to allow any language."
                )
            }

            Section {
                Toggle("Show while listening", isOn: $preferences.showsCaptions)
                Picker("Text Size", selection: $captionSize) {
                    Text("Small").tag(CaptionTextSize.small)
                    Text("Medium").tag(CaptionTextSize.medium)
                    Text("Large").tag(CaptionTextSize.large)
                }
                .pickerStyle(.segmented)
                .disabled(!preferences.showsCaptions)
            } header: {
                Text("Captions Overlay")
            } footer: {
                Text(
                    "People see the overlay when you share your whole screen. Share a single window to keep it to yourself."
                )
            }

            Section("App") {
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
    }

    private func chooseTranscriptsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        try? controller.preferences.setTranscriptsFolder(folder)
        // Until the import of 0.1's transcripts finishes once, it runs on the folder chosen.
        Task { await controller.importEarlierTranscripts() }
    }
}

struct MicrophoneSettings: View {
    @Environment(SessionController.self) private var controller
    @State private var inputs: [AudioDevices.Input] = []

    var body: some View {
        @Bindable var preferences = controller.preferences
        Form {
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
        }
        .formStyle(.grouped)
        .onAppear { inputs = AudioDevices.inputs() }
    }
}

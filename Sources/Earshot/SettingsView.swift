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

    var body: some View {
        @Bindable var controller = controller
        @Bindable var preferences = controller.preferences
        Form {
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

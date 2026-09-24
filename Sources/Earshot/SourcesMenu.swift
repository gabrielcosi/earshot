import EarshotCapture
import SwiftUI

/// Picks the apps to transcribe from those playing sound, or every app. It can change while
/// listening: the capture switches over without stopping.
struct SourcesMenu: View {
    @Environment(SessionController.self) private var controller
    /// Apps playing sound when the menu bar window opened.
    @State private var playing: [AudioSource] = []

    var body: some View {
        Menu(summary) {
            Button("All apps") { controller.sources = [] }
            Divider()
            if choices.isEmpty {
                Text("No other app is playing sound")
            }
            ForEach(choices) { source in
                Toggle(source.name, isOn: binding(for: source))
            }
        }
        .onAppear { playing = AudioSources.playing() }
    }

    /// Chosen apps stay listed while they are silent, so they can be unchosen.
    private var choices: [AudioSource] {
        controller.sources + playing.filter { !controller.sources.contains($0) }
    }

    private var summary: String {
        switch controller.sources.count {
        case 0: "All apps"
        case 1: controller.sources[0].name
        case let count: "\(count) apps"
        }
    }

    private func binding(for source: AudioSource) -> Binding<Bool> {
        Binding(
            get: { controller.sources.contains(source) },
            set: { chosen in
                controller.sources.removeAll { $0 == source }
                if chosen { controller.sources.append(source) }
            })
    }
}

import SwiftUI

extension FocusedValues {
    /// The player of the transcript in the key window, when its audio was kept.
    @Entry var transcriptPlayer: TranscriptPlayer?
}

/// Play and Pause on Space, in a Controls menu as in Music and Podcasts. A focused text field or
/// text view takes Space before the menu does, so typing a space never plays; with no player in
/// the key window the item is disabled, and a disabled item leaves Space to the focused control.
/// The sidebar's list takes Space before the menu does, so it plays and pauses there itself.
struct PlaybackCommands: Commands {
    @FocusedValue(\.transcriptPlayer) private var player

    var body: some Commands {
        CommandMenu("Controls") {
            Button(player?.isPlaying == true ? "Pause" : "Play") { player?.toggle() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player == nil)
        }
    }
}

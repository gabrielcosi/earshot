import AppKit
import EarshotKit
import SwiftUI

/// The View menu's text size, and Check for Updates in the app menu, where Mac apps keep them.
struct TranscriptCommands: Commands {
    let updater: Updater
    @AppStorage(TranscriptSettings.textSize) private var textSize = TranscriptTextSize.standard
    @AppStorage(TranscriptSettings.display) private var display = TranslationDisplay.both

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            mode(.original, key: "1")
            mode(.both, key: "2")
            mode(.translation, key: "3")
            Divider()
            Button("Zoom In") { textSize = TranscriptTextSize.larger(than: textSize) }
                .keyboardShortcut("+")
            Button("Zoom Out") { textSize = TranscriptTextSize.smaller(than: textSize) }
                .keyboardShortcut("-")
            Button("Actual Size") { textSize = TranscriptTextSize.standard }
                .keyboardShortcut("0")
            Divider()
        }
        CommandGroup(after: .appInfo) {
            if updater.isAvailable {
                Button("Check for Updates…") { updater.check() }
                    .disabled(!updater.canCheck)
            }
        }
    }

    private func mode(_ mode: TranslationDisplay, key: KeyEquivalent) -> some View {
        Toggle(
            mode.title, isOn: Binding(get: { display == mode }, set: { if $0 { display = mode } })
        )
        .keyboardShortcut(key)
    }

    /// ⌘= zooms in too, the unshifted key under "+" on most layouts, as in Safari and Notes. A
    /// hidden duplicate menu item would not do it: hidden items take no part in key equivalent
    /// matching (NSMenuItem.h) unless `allowsKeyEquivalentWhenHidden`, which SwiftUI does not set.
    static func zoomInWithEquals() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Caps Lock, and the keypad's flag on its "=", do not change which key this is.
            guard
                event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                event.charactersIgnoringModifiers == "="
            else { return event }
            let defaults = UserDefaults.standard
            let size = defaults.object(forKey: TranscriptSettings.textSize) as? Double
            defaults.set(
                TranscriptTextSize.larger(than: size ?? TranscriptTextSize.standard),
                forKey: TranscriptSettings.textSize)
            return nil
        }
    }
}

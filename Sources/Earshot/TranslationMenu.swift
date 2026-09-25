import EarshotKit
import SwiftUI

/// Picks the language everything else is translated into, or no translation. The same two
/// settings as in Settings, so both always show the same choice.
struct TranslationMenu: View {
    @Environment(SessionController.self) private var controller

    var body: some View {
        Menu(summary) {
            Toggle("Off", isOn: binding(for: nil))
            Divider()
            ForEach(controller.translationChoices, id: \.self) { code in
                Toggle(Languages.displayName(code), isOn: binding(for: code))
            }
        }
    }

    private var summary: String {
        controller.translationEnabled ? Languages.displayName(controller.primaryLanguage) : "Off"
    }

    /// Choosing a language turns translation on; each setting changes only when its value does,
    /// since changing one drops the translations in flight and starts them again.
    private func binding(for code: String?) -> Binding<Bool> {
        Binding(
            get: {
                code.map { controller.translationEnabled && controller.primaryLanguage == $0 }
                    ?? !controller.translationEnabled
            },
            set: { selected in
                guard selected else { return }
                if let code, controller.primaryLanguage != code {
                    controller.primaryLanguage = code
                }
                if controller.translationEnabled != (code != nil) {
                    controller.translationEnabled = code != nil
                }
            })
    }
}

extension SessionController {
    /// The languages Apple translates into, and the current one, by name.
    var translationChoices: [String] {
        let codes = Set(translationLanguages.map(\.minimalIdentifier)).union([primaryLanguage])
        return codes.sorted { Languages.displayName($0) < Languages.displayName($1) }
    }
}

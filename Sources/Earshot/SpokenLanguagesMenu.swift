import EarshotKit
import SwiftUI

/// Picks the languages spoken in what is transcribed. None picked means any language.
struct SpokenLanguagesMenu: View {
    @Environment(SessionController.self) private var controller

    var body: some View {
        Menu(Languages.summary(controller.spokenLanguages)) {
            Button("Any language") { controller.spokenLanguages = [] }
            Divider()
            ForEach(Languages.codes, id: \.self) { code in
                Toggle(Languages.displayName(code), isOn: binding(for: code))
            }
        }
        .disabled(controller.state != .idle)
    }

    private func binding(for code: String) -> Binding<Bool> {
        Binding(
            get: { controller.spokenLanguages.contains(code) },
            set: { selected in
                controller.spokenLanguages.removeAll { $0 == code }
                if selected { controller.spokenLanguages.append(code) }
            })
    }
}

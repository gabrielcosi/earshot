import EarshotKit
import SwiftUI

/// The vocabulary the engine favours, and the rules that tidy transcripts.
struct WordsView: View {
    @Environment(SessionController.self) private var controller
    @State private var sample = "Uh, so um we asked John Doe about the acme corp deal."
    @State private var newTerm = ""

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Preview") {
                TextField("Type a sample…", text: $sample, axis: .vertical)
                LabeledContent("Result") {
                    Text(controller.rules.apply(sample)).textSelection(.enabled)
                }
            }

            Section {
                ForEach(controller.rules.vocabulary.indices, id: \.self) { index in
                    HStack {
                        TextField("Term", text: $controller.rules.vocabulary[index])
                            .labelsHidden()
                        Button("Remove", systemImage: "trash") {
                            controller.rules.vocabulary.remove(at: index)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Add a name or term", text: $newTerm)
                        .labelsHidden()
                        .onSubmit(addTerm)
                    Button("Add", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Vocabulary")
            } footer: {
                Text(
                    "Names, products, and jargon the recognizer should favour. Applies from the next time you start listening."
                )
            }

            Section {
                Toggle("Remove words", isOn: $controller.rules.removalEnabled)
                ForEach($controller.rules.removals) { $removal in
                    HStack {
                        Toggle("On", isOn: $removal.enabled).labelsHidden()
                        TextField("Pattern", text: $removal.pattern).labelsHidden()
                        if let language = removal.language {
                            Text("\(Languages.displayName(language)) only")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Delete", systemImage: "trash") {
                            controller.rules.removals.removeAll { $0.id == removal.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                    .disabled(!controller.rules.removalEnabled)
                }
                Button("Add Pattern", systemImage: "plus") {
                    controller.rules.removals.append(WordRules.Removal(pattern: ""))
                }
            } header: {
                Text("Remove")
            } footer: {
                Text(
                    "Whole words, ignoring case; patterns are regular expressions. \"er\" is left out on purpose: it is German for \"he\"."
                )
            }

            Section {
                Toggle("Replace words", isOn: $controller.rules.replacementEnabled)
                ForEach($controller.rules.replacements) { $replacement in
                    HStack {
                        Toggle("On", isOn: $replacement.enabled).labelsHidden()
                        TextField("Pattern", text: $replacement.pattern).labelsHidden()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Replacement", text: $replacement.replacement).labelsHidden()
                        Button("Delete", systemImage: "trash") {
                            controller.rules.replacements.removeAll { $0.id == replacement.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                    .disabled(!controller.rules.replacementEnabled)
                }
                Button("Add Replacement", systemImage: "plus") {
                    controller.rules.replacements.append(
                        WordRules.Replacement(pattern: "", replacement: ""))
                }
            } header: {
                Text("Replace")
            }

            Section {
                Toggle("Lowercase", isOn: $controller.rules.lowercase)
                Toggle("Remove punctuation", isOn: $controller.rules.removePunctuation)
            } header: {
                Text("Formatting")
            } footer: {
                Text(
                    "Rules change how transcripts are shown and saved, never what was recorded, so older transcripts follow new rules too."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Words")
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        controller.rules.vocabulary.append(term)
        newTerm = ""
    }
}

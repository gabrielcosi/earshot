import EarshotKit
import SwiftUI

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

/// The model library: download models and choose which ones Earshot uses.
struct ModelSettings: View {
    @Environment(SessionController.self) private var controller

    var body: some View {
        let library = controller.library
        Form {
            Section {
                ForEach(library.catalog.models(for: .transcription)) { row($0) }
            } header: {
                Text("Transcription")
            } footer: {
                if library.selection == nil {
                    Text("Earshot needs a transcription model before it can listen.")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(library.catalog.models(for: .diarization)) { row($0) }
            } header: {
                Text("Speaker detection")
            } footer: {
                if !library.installed.contains(library.diarization) {
                    Text("Without one, transcripts have no speaker labels.")
                }
            }
            if let error = library.lastError {
                Text(error).foregroundStyle(.red)
            }
            Section {
                Label("Models are stored and run on this Mac.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                .accessibilityHidden(true)
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
                    Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
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

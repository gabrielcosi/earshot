import EarshotKit
import Foundation

/// Translation of the live transcript: partials as they grow, paragraphs when they finish.
extension SessionController {
    func translatePending() {
        guard translationEnabled else { return }
        let target = Locale.Language(identifier: primaryLanguage)
        for utterance in transcript.utterances
        where utterance.currentTranslation == nil && attempted[utterance.id] != utterance.text {
            let (id, text) = (utterance.id, utterance.text)
            attempted[id] = text
            Task {
                do {
                    switch try await translator.translate(text, to: target, pass: .final) {
                    case .translated(let translated):
                        transcript.setTranslation(
                            EarshotKit.Translation(sourceText: text, text: translated), for: id)
                        save()
                    case .needsDownload(let source):
                        if downloadRequest == nil {
                            downloadRequest = .init(source: source, target: target)
                        }
                    case .notNeeded, .unsupported:
                        break
                    }
                } catch {
                    log.error("translation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Re-translates a channel's partial as it grows. One request per channel at a time; a partial
    /// that changes meanwhile is picked up when the request returns, so the newest text wins.
    func translateLive(_ channel: Channel) {
        guard translationEnabled else { return }
        guard !liveInFlight.contains(channel) else {
            liveStale.insert(channel)
            return
        }
        guard let text = transcript.partials[channel], !text.isEmpty else { return }
        let target = Locale.Language(identifier: primaryLanguage)
        liveInFlight.insert(channel)
        Task {
            if case .translated(let translated) = try? await translator.translate(
                text, to: target, pass: .live)
            {
                transcript.setLiveTranslation(
                    EarshotKit.Translation(sourceText: text, text: translated), on: channel)
            }
            liveInFlight.remove(channel)
            if liveStale.remove(channel) != nil { translateLive(channel) }
        }
    }

}

import EarshotKit
import Foundation
@preconcurrency import Translation

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
                        keepTranslation(
                            translated, of: text, language: target.minimalIdentifier, for: id)
                    case .needsDownload(let source):
                        report(
                            .translationNeedsDownload(
                                from: source.minimalIdentifier, to: target.minimalIdentifier))
                        settle(id, text)
                    case .unsupported(let source):
                        report(
                            .translationUnsupported(
                                from: source.minimalIdentifier, to: target.minimalIdentifier))
                        settle(id, text)
                    case .notNeeded:
                        settle(id, text)
                    }
                } catch {
                    log.error("translation failed: \(error.localizedDescription)")
                    settle(id, text)
                }
            }
        }
    }

    /// An outcome for text no longer being tried, after a reset or as the paragraph grew, is
    /// not recorded.
    private func settle(_ id: UUID, _ text: String) {
        if attempted[id] == text { settledTranslations.insert(id) }
    }

    /// Stores a translation of what the paragraph says now. One that lands after the session
    /// ended updates its Markdown file too.
    private func keepTranslation(
        _ translated: String, of text: String, language: String, for id: UUID
    ) {
        guard let savedID,
            transcript.utterances.contains(where: { $0.id == id && $0.text == text })
        else { return }
        do {
            try store.setTranslation(translated, of: text, language: language, for: id)
        } catch {
            reportSavingFailed(error)
        }
        if sealed { scheduleExport(savedID) }
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

    /// Whether showing translations alone shows nothing for a finished line yet: its
    /// translation is still to come.
    func awaitsTranslation(_ line: TranscriptLine) -> Bool {
        translationEnabled
            && TranslationWait.pending(
                translation: line.translation,
                settled: UUID(uuidString: line.id).map(settledTranslations.contains) ?? true)
    }

    /// The same for words still being recognized, which get no recorded outcome: a pair that
    /// needs a download or is unsupported shows them as they are.
    func awaitsTranslation(live text: String, translation: String?) -> Bool {
        let unavailable = problems.all.compactMap { problem -> String? in
            switch problem {
            case .translationNeedsDownload(let source, _), .translationUnsupported(let source, _):
                source
            default: nil
            }
        }
        return translationEnabled
            && TranslationWait.pending(
                live: text, translation: translation, into: primaryLanguage,
                unavailable: unavailable)
    }

    /// Asks for Apple's download prompt for a language pair; the main window presents it.
    func requestDownload(from source: String, to target: String) {
        downloadRequest = .init(
            source: Locale.Language(identifier: source), target: Locale.Language(identifier: target)
        )
    }

    /// A translation that returns after translation was turned off or the language changed
    /// reports nothing: its problem was resolved when that happened.
    private func report(_ problem: Problem) {
        let current = Locale.Language(identifier: primaryLanguage).minimalIdentifier
        switch problem {
        case .translationNeedsDownload(_, let target), .translationUnsupported(_, let target):
            guard translationEnabled, target == current else { return }
        default:
            break
        }
        problems.report(problem)
    }

    /// The pair is installed: its problem goes, and what waited for it is translated.
    func downloadFinished(from source: Locale.Language?, to target: Locale.Language?) {
        if let source, let target {
            let installed = Problem.translationNeedsDownload(
                from: source.minimalIdentifier, to: target.minimalIdentifier)
            problems.resolve { $0 == installed }
        }
        endDownload(from: source, to: target)
        attempted = [:]
        settledTranslations = []
        translatePending()
    }

    /// Declined or failed: the problem stays, so the download can be asked for again.
    func downloadFailed(
        from source: Locale.Language?, to target: Locale.Language?, _ error: any Error
    ) {
        log.error("translation download failed: \(error.localizedDescription)")
        endDownload(from: source, to: target)
    }

    /// Clears the request only if it is still this one; the user may have asked for another pair.
    private func endDownload(from source: Locale.Language?, to target: Locale.Language?) {
        guard downloadRequest?.source?.minimalIdentifier == source?.minimalIdentifier,
            downloadRequest?.target?.minimalIdentifier == target?.minimalIdentifier
        else { return }
        downloadRequest = nil
    }

}

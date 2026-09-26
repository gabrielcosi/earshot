import EarshotKit
import Foundation
@preconcurrency import Translation

/// Translation of the live transcript, one request at a time: each finished sentence once, and
/// each channel's words in flight as they grow, taking turns.
extension SessionController {
    /// Measured on Apple silicon (docs/behaviour.md, Apple Translation): `.lowLatency` takes
    /// 20-110 ms a sentence. `.highFidelity` takes 0.4-0.9 s, and a request right after one of the
    /// other strategy's takes 300-400 ms longer, so words in flight waiting behind a
    /// `.highFidelity` sentence would wait more than a second. Both use `.lowLatency`.
    static let translationStrategy = TranslationSession.Strategy.lowLatency

    private static let clockOrigin = ContinuousClock.now

    /// Seconds on a clock that only goes forward, for the queue and the log.
    var translationClock: Double { (ContinuousClock.now - Self.clockOrigin) / .seconds(1) }

    /// Starts over, at a start, a change of language, or when translation is turned on. Turned
    /// off, what was translated stays and nothing more is asked for. Every reset cancels the
    /// worker, which is how a request that returns after one changes nothing.
    func resetTranslations() {
        translationWorker?.cancel()
        translationWorker = nil
        translationQueue = TranslationQueue()
        unavailablePairs = UnavailablePairs()
        if translationEnabled {
            transcript.translate(into: primaryLanguage)
        } else {
            transcript.dropLiveTranslations()
        }
        translationChanged()
    }

    /// After every change to the transcript: what settled is stored, and what is missing waits
    /// for the translator.
    func translationChanged() {
        storeTranslations()
        guard translationEnabled else { return }
        for channel in Channel.allCases where transcript.partials[channel] == nil {
            translationQueue.live(nil, on: channel, at: translationClock)
        }
        translationQueue.demand(transcript.pendingSentences, at: translationClock)
        runTranslations()
    }

    /// A channel's words in flight changed; only the latest are translated.
    func translateLive(_ channel: Channel) {
        guard translationEnabled else { return }
        translationQueue.live(transcript.partials[channel], on: channel, at: translationClock)
        runTranslations()
    }

    /// Runs until nothing waits. The translator cannot stop a request early
    /// (docs/behaviour.md, Apple Translation), so one that returns after a reset is dropped.
    private func runTranslations() {
        guard translationWorker == nil else { return }
        translationWorker = Task {
            while !Task.isCancelled, let started = translationQueue.next() {
                let (depth, begun) = (translationQueue.depth, translationClock)
                let language = primaryLanguage
                let target = Locale.Language(identifier: language)
                let (text, context): (String, String?) =
                    switch started.job {
                    case .live(let text, _): (text, nil)
                    case .sentence(let request): (request.text, request.paragraph)
                    }
                let result: Result<Translator.Outcome, any Error>
                do {
                    result = .success(
                        try await translator.translate(
                            text, context: context, to: target, strategy: Self.translationStrategy))
                } catch {
                    result = .failure(error)
                }
                guard !Task.isCancelled else { return }
                let outcome = Self.outcome(of: result)
                let isLive = if case .live = started.job { true } else { false }
                let entry = TranslationLog.Entry(
                    kind: isLive ? .live : .sentence, characters: text.count,
                    wait: begun - started.queuedAt, took: translationClock - begun, depth: depth,
                    outcome: outcome)
                translationQueue.finish()
                switch started.job {
                case .live(let text, let channel):
                    if case .translated(let translated) = outcome {
                        transcript.setLiveTranslation(
                            EarshotKit.Translation(sourceText: text, text: translated), on: channel)
                    }
                    // Words in flight learn first that a pair is unavailable, a sentence only
                    // once its final lands; until then they would wait for nothing.
                    if case .success = result {
                        reportUnavailable(result, into: target, bySentence: false)
                    }
                case .sentence(let request):
                    reportUnavailable(result, into: target, bySentence: true)
                    transcript.record(outcome, for: request.text, into: language)
                    translationChanged()
                }
                translationLog.record(entry)
            }
            if !Task.isCancelled { translationWorker = nil }
        }
    }

    private static func outcome(of result: Result<Translator.Outcome, any Error>)
        -> SentenceOutcome
    {
        switch result {
        case .success(.translated(let text)): .translated(text)
        case .success(.notNeeded): .kept
        case .success(.needsDownload), .success(.unsupported): .unavailable
        case .failure: .failed
        }
    }

    /// A pair that needs a download or is unsupported is reported once, by a sentence, not for
    /// every sentence: a problem the user dismissed would come back with the next one. Its source
    /// language is kept, so words in flight in it show as they are even once it is dismissed.
    private func reportUnavailable(
        _ result: Result<Translator.Outcome, any Error>, into target: Locale.Language,
        bySentence: Bool
    ) {
        let problem: Problem
        switch result {
        case .success(.needsDownload(let source)):
            problem = .translationNeedsDownload(
                from: source.minimalIdentifier, to: target.minimalIdentifier)
        case .success(.unsupported(let source)):
            problem = .translationUnsupported(
                from: source.minimalIdentifier, to: target.minimalIdentifier)
        case .failure(let error):
            log.error("translation failed: \(error.localizedDescription)")
            return
        case .success: return
        }
        if let report = unavailablePairs.found(problem, bySentence: bySentence) {
            problems.report(report)
        }
    }

    /// Stores each settled paragraph's translation, and again whenever it changes: another
    /// language, or a sentence translated after a download. One that lands after the session
    /// ended updates its Markdown file.
    private func storeTranslations() {
        guard let savedID else { return }
        let changed = transcript.translationsToStore(besides: savedTranslations)
        for (id, translation) in changed {
            do {
                try store.setTranslation(
                    translation.text, of: translation.source, language: translation.language,
                    for: id)
            } catch {
                return reportSavingFailed(error)
            }
            savedTranslations[id] = translation
        }
        if !changed.isEmpty, sealed { scheduleExport(savedID) }
    }

    /// Whether showing translations alone shows nothing for a finished line yet: its
    /// translation is still to come.
    func awaitsTranslation(_ line: TranscriptLine) -> Bool {
        translationEnabled
            && TranslationWait.pending(
                translation: line.translation, started: line.translationStarted)
    }

    /// The same for words still being recognized, which get no recorded outcome: words in a
    /// language whose pair needs a download or is unsupported show as they are.
    func awaitsTranslation(live text: String, translation: String?) -> Bool {
        translationEnabled
            && TranslationWait.pending(
                live: text, translation: translation, into: primaryLanguage,
                unavailable: Array(unavailablePairs.sources))
    }

    /// Asks for Apple's download prompt for a language pair; the main window presents it. The
    /// strategy is the one translations use: without it, the prompt offers the `.highFidelity`
    /// models, and returns at once without a prompt where those are installed but the
    /// `.lowLatency` ones are not.
    func requestDownload(from source: String, to target: String) {
        translationLog.download(.requested, from: source, to: target)
        downloadRequest = .init(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: target),
            preferredStrategy: Self.translationStrategy)
    }

    /// The pair is installed: its problem goes, and what waited for it is translated.
    func downloadFinished(from source: Locale.Language?, to target: Locale.Language?) {
        translationLog.download(
            .finished, from: source?.minimalIdentifier, to: target?.minimalIdentifier)
        if let source, let target {
            let installed = Problem.translationNeedsDownload(
                from: source.minimalIdentifier, to: target.minimalIdentifier)
            problems.resolve { $0 == installed }
        }
        endDownload(from: source, to: target)
        unavailablePairs = UnavailablePairs()
        transcript.forgetUnavailable()
        translationChanged()
    }

    /// Declined or failed: the problem stays, so the download can be asked for again.
    func downloadFailed(
        from source: Locale.Language?, to target: Locale.Language?, _ error: any Error
    ) {
        translationLog.download(
            .failed, from: source?.minimalIdentifier, to: target?.minimalIdentifier)
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

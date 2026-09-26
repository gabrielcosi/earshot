import Foundation

/// What translating one sentence gave.
public enum SentenceOutcome: Sendable, Equatable {
    case translated(String)
    /// Already in the target language, or too short to tell: shown as it is.
    case kept
    /// Its language pair needs a download or is unsupported.
    case unavailable
    case failed
}

/// A paragraph's translation as it shows: the translations of its sentences in order, as far as
/// every sentence before has one, then the live translation carried from its latest final until
/// a sentence of that final's has an outcome. Sentences kept, unavailable, or failed show as they
/// were said.
public struct ParagraphTranslation: Sendable, Equatable {
    /// Nil when nothing is translated: every sentence so far stays as it was said.
    public let text: String?
    /// Every sentence has an outcome, so `text` is the whole paragraph's and nothing more comes.
    public let settled: Bool
    /// A sentence has an outcome. A line shows from then on, even while a sentence merged into it
    /// later waits for its own.
    public let started: Bool

    public static let untranslated = ParagraphTranslation(text: nil, settled: true, started: true)

    /// `target` is nil while nothing is translated. `carried` translates the sentences from
    /// `carriedFrom` on; once one of those has its own outcome, showing both would say it twice.
    static func compose(
        _ sentences: [String], outcomes: [String: SentenceOutcome], carried: String?,
        from carriedFrom: Int, into target: String?
    ) -> ParagraphTranslation {
        guard let target else { return .untranslated }
        var parts: [String] = []
        var translated = false
        for sentence in sentences {
            switch outcomes[sentence] {
            case .translated(let text):
                parts.append(text)
                translated = true
            case .kept, .unavailable, .failed:
                parts.append(sentence)
            case nil:
                if let carried,
                    !sentences.dropFirst(carriedFrom).contains(where: { outcomes[$0] != nil })
                {
                    parts.append(carried)
                    translated = true
                }
                return ParagraphTranslation(
                    text: translated ? Sentences.join(parts, into: target) : nil, settled: false,
                    started: sentences.contains { outcomes[$0] != nil })
            }
        }
        return ParagraphTranslation(
            text: translated ? Sentences.join(parts, into: target) : nil, settled: true,
            started: true)
    }
}

/// A settled paragraph's translation as the store keeps it: what it translates, into which
/// language, and the text, nil when every sentence stays as it was said.
public struct StoredTranslation: Sendable, Equatable {
    public let source: String
    public let language: String
    public let text: String?
}

/// A sentence waiting for its translation, with its paragraph, whose language stands in when
/// the sentence alone is too short to tell ("Ja.").
public struct SentenceRequest: Sendable, Equatable {
    public let text: String
    public let paragraph: String
}

/// The session's sentence translations, and each paragraph's composed from them.
extension Transcript {
    /// Starts translating into `target`, forgetting every outcome.
    public mutating func translate(into target: String) {
        translationTarget = target
        outcomes = [:]
        dropLiveTranslations()
    }

    /// The settled paragraphs whose translation is not what `stored` holds for them: new, in
    /// another language, fuller once a sentence was translated after a download, or none any
    /// more, when the target became the language spoken.
    public func translationsToStore(besides stored: [UUID: StoredTranslation])
        -> [UUID: StoredTranslation]
    {
        guard let translationTarget else { return [:] }
        let language = Locale.Language(identifier: translationTarget).minimalIdentifier
        var changed: [UUID: StoredTranslation] = [:]
        for utterance in utterances where utterance.translation.settled {
            let text = utterance.translation.text
            guard text != nil || stored[utterance.id]?.text != nil else { continue }
            let translation = StoredTranslation(
                source: utterance.text, language: language, text: text)
            if stored[utterance.id] != translation { changed[utterance.id] = translation }
        }
        return changed
    }

    /// A language pair was installed: what was unavailable is tried again.
    public mutating func forgetUnavailable() {
        outcomes = outcomes.filter { $0.value != .unavailable }
        composeAll()
    }

    /// An outcome made for another target, before the language changed, is not recorded.
    public mutating func record(
        _ outcome: SentenceOutcome, for sentence: String, into target: String
    ) {
        guard target == translationTarget else { return }
        outcomes[sentence] = outcome
        for index in utterances.indices
        where !utterances[index].translation.settled
            && utterances[index].sentences.contains(sentence)
        {
            compose(at: index)
        }
    }

    /// Sentences without an outcome, the newest paragraph first and each paragraph's in order:
    /// the newest are the ones being read.
    public var pendingSentences: [SentenceRequest] {
        guard translationTarget != nil else { return [] }
        var seen: Set<String> = []
        return utterances.reversed().filter { !$0.translation.settled }.flatMap { utterance in
            utterance.sentences.filter { outcomes[$0] == nil && seen.insert($0).inserted }
                .map { SentenceRequest(text: $0, paragraph: utterance.text) }
        }
    }

    /// How many of the paragraphs' different sentences have an outcome, and how many are pending.
    public var sentenceCoverage: (known: Int, pending: Int) {
        let all = Set(utterances.flatMap(\.sentences))
        let known = all.filter { outcomes[$0] != nil }.count
        return (known, all.count - known)
    }
}

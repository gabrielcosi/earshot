import EarshotKit
import Foundation
@preconcurrency import Translation

/// Translates speech into the user's language with Apple's on-device models.
final class Translator {
    enum Outcome {
        case translated(String)
        /// Already in the target language, or too short to tell.
        case notNeeded
        /// The language pair exists but its models are not downloaded yet.
        case needsDownload(source: Locale.Language)
        case unsupported(source: Locale.Language)
    }

    private var sessions: [String: TranslationSession] = [:]
    private let lowLatency = LanguageAvailability(preferredStrategy: .lowLatency)

    /// `context` is the paragraph around `text`: its language stands in when `text` alone is too
    /// short to tell. Where Apple Intelligence is off, `.highFidelity` falls back to the
    /// `.lowLatency` models on its own.
    func translate(
        _ text: String, context: String?, to target: Locale.Language,
        strategy: TranslationSession.Strategy
    ) async throws -> Outcome {
        guard let source = LanguageDetection.dominant(text, within: context),
            !LanguageDetection.sameLanguage(source, target)
        else { return .notNeeded }
        switch await LanguageAvailability(preferredStrategy: strategy)
            .status(from: source, to: target)
        {
        case .installed: break
        case .supported: return .needsDownload(source: source)
        case .unsupported: return .unsupported(source: source)
        @unknown default: return .unsupported(source: source)
        }
        return .translated(
            try await session(from: source, to: target, strategy: strategy).translate(text)
                .targetText)
    }

    /// One session per pair and strategy, kept for the requests after it.
    private func session(
        from source: Locale.Language, to target: Locale.Language,
        strategy: TranslationSession.Strategy
    ) -> TranslationSession {
        let key = "\(source.minimalIdentifier)>\(target.minimalIdentifier)>\(strategy)"
        if let session = sessions[key] { return session }
        let session = TranslationSession(
            installedSource: source, target: target, preferredStrategy: strategy)
        sessions[key] = session
        return session
    }

    func supportedLanguages() async -> [Locale.Language] {
        await lowLatency.supportedLanguages
    }

    /// Sessions are bound to a target; drop them when the user picks a different language.
    func reset() {
        sessions = [:]
    }
}

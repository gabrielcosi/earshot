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
        case unsupported
    }

    /// Measured on Apple silicon: low latency takes 20-35 ms a sentence, fast enough to redo on every
    /// partial; high fidelity reads better but takes 0.4-0.6 s, so it runs once per final.
    enum Pass {
        case live
        case final

        var strategy: TranslationSession.Strategy {
            switch self {
            case .live: .lowLatency
            case .final: .highFidelity
            }
        }
    }

    private var sessions: [String: TranslationSession] = [:]
    private let lowLatency = LanguageAvailability(preferredStrategy: .lowLatency)
    private let highFidelity = LanguageAvailability(preferredStrategy: .highFidelity)

    func translate(_ text: String, to target: Locale.Language, pass: Pass) async throws -> Outcome {
        guard let source = LanguageDetection.dominant(text),
            !LanguageDetection.sameLanguage(source, target)
        else { return .notNeeded }

        var strategy = pass.strategy
        if strategy == .highFidelity,
            await highFidelity.status(from: source, to: target) != .installed
        {
            strategy = .lowLatency
        }
        switch await lowLatency.status(from: source, to: target) {
        case .installed: break
        case .supported: return .needsDownload(source: source)
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }

        let key = "\(source.minimalIdentifier)>\(target.minimalIdentifier)>\(strategy)"
        let session =
            sessions[key]
            ?? TranslationSession(
                installedSource: source, target: target, preferredStrategy: strategy)
        sessions[key] = session
        return .translated(try await session.translate(text).targetText)
    }

    func supportedLanguages() async -> [Locale.Language] {
        await lowLatency.supportedLanguages
    }

    /// Sessions are bound to a target; drop them when the user picks a different language.
    func reset() {
        sessions = [:]
    }
}

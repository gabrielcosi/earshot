import Foundation
import os

/// The translation pipeline's timing, in the `translation` log category. Numbers and fixed words
/// only: no transcript text is ever interpolated.
struct TranslationLog {
    enum Kind: String {
        case paragraph
        case live
    }

    enum Result: String {
        case translated
        case kept
        case unavailable
        case failed
    }

    /// One request: what it was, how long it waited to start and took, what it gave, the
    /// requests waiting or running beside it, and for a paragraph, how long after its final.
    struct Entry {
        let kind: Kind
        let strategy: String
        let characters: Int
        let wait: Double
        let took: Double
        let depth: Int
        let result: Result
        let latency: Double?
    }

    private let logger = Logger(subsystem: "com.gabrielcosi.earshot", category: "translation")
    /// Paragraph requests started and not yet returned.
    var inFlight = 0
    private var jobs = 0
    private var characters = 0
    private var took: [Double] = []
    private var latency: [Double] = []
    private var deepest = 0

    /// A paragraph's request is a `.notice`, about one every few seconds of speech, kept for a
    /// recorded session's diagnosis. A partial's is a `.debug`: they come many times a second and
    /// are seen only in `log stream --level debug`.
    mutating func record(_ entry: Entry) {
        let (kind, strategy, count, depth) = (
            entry.kind.rawValue, entry.strategy, entry.characters, entry.depth
        )
        let (wait, took, result) = (
            Self.milliseconds(entry.wait), Self.milliseconds(entry.took), entry.result.rawValue
        )
        switch entry.kind {
        case .live:
            logger.debug(
                "kind=\(kind, privacy: .public) strategy=\(strategy, privacy: .public) chars=\(count) wait_ms=\(wait) took_ms=\(took) depth=\(depth) outcome=\(result, privacy: .public)"
            )
        case .paragraph:
            logger.notice(
                "kind=\(kind, privacy: .public) strategy=\(strategy, privacy: .public) chars=\(count) wait_ms=\(wait) took_ms=\(took) depth=\(depth) outcome=\(result, privacy: .public)"
            )
            jobs += 1
            characters += count
            self.took.append(entry.took)
            if let latency = entry.latency { self.latency.append(latency) }
            deepest = max(deepest, depth)
        }
    }

    /// The session's figures, when it stops; they start again from zero.
    mutating func summarize() {
        let (jobs, characters, deepest) = (jobs, characters, deepest)
        let took = (Self.percentile(took, 0.5), Self.percentile(took, 0.9))
        let latency = (Self.percentile(latency, 0.5), Self.percentile(latency, 0.9))
        logger.notice(
            "summary jobs=\(jobs) chars=\(characters) took_p50_ms=\(Self.milliseconds(took.0)) took_p90_ms=\(Self.milliseconds(took.1)) latency_p50_ms=\(Self.milliseconds(latency.0)) latency_p90_ms=\(Self.milliseconds(latency.1)) max_depth=\(deepest)"
        )
        self = TranslationLog()
    }

    private static func milliseconds(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[Int((Double(sorted.count - 1) * fraction).rounded())]
    }
}

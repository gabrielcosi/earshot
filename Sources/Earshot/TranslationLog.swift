import EarshotKit
import Foundation
import os

/// The translation pipeline's timing, in the `translation` log category. Numbers and fixed words
/// only: no transcript text is ever interpolated.
struct TranslationLog {
    enum Kind: String {
        case sentence
        case live
    }

    /// One request: what it was, how long it waited to start and took, what it gave, and the
    /// sentences left waiting. It waits from when it was first asked for: for a sentence, the
    /// final, refinement, or relabelling that made it.
    struct Entry {
        let kind: Kind
        let characters: Int
        let wait: Double
        let took: Double
        let depth: Int
        let outcome: SentenceOutcome
    }

    /// A language pair's download, as it goes through Apple's prompt.
    enum Download: String {
        case requested
        case started
        case finished
        case failed
    }

    private let logger = Logger(subsystem: "com.gabrielcosi.earshot", category: "translation")
    private var jobs = 0
    private var characters = 0
    private var took: [Double] = []
    private var latency: [Double] = []
    private var deepest = 0
    private var relabel: (hits: Int, misses: Int)?

    /// A sentence's request is a `.notice`, about one every few seconds of speech, kept for a
    /// recorded session's diagnosis. A partial's is a `.debug`: they come many times a second and
    /// are seen only in `log stream --level debug`.
    mutating func record(_ entry: Entry) {
        let (kind, count, depth) = (entry.kind.rawValue, entry.characters, entry.depth)
        let (wait, took) = (Self.milliseconds(entry.wait), Self.milliseconds(entry.took))
        let result =
            switch entry.outcome {
            case .translated: "translated"
            case .kept: "kept"
            case .unavailable: "unavailable"
            case .failed: "failed"
            }
        switch entry.kind {
        case .live:
            logger.debug(
                "kind=\(kind, privacy: .public) chars=\(count) wait_ms=\(wait) took_ms=\(took) depth=\(depth) outcome=\(result, privacy: .public)"
            )
        case .sentence:
            logger.notice(
                "kind=\(kind, privacy: .public) chars=\(count) wait_ms=\(wait) took_ms=\(took) depth=\(depth) outcome=\(result, privacy: .public)"
            )
            jobs += 1
            characters += count
            self.took.append(entry.took)
            latency.append(entry.wait + entry.took)
            deepest = max(deepest, depth)
        }
    }

    /// Sentences of the paragraphs rebuilt at the end of a session that were already translated,
    /// and those that were not.
    mutating func relabelled(hits: Int, misses: Int) {
        relabel = (hits, misses)
    }

    /// Language codes only, which say nothing of what was said.
    func download(_ step: Download, from source: String?, to target: String?) {
        let (step, source, target) = (step.rawValue, source ?? "any", target ?? "any")
        logger.notice(
            "download=\(step, privacy: .public) from=\(source, privacy: .public) to=\(target, privacy: .public)"
        )
    }

    /// The session's figures, once relabelling at its end is done: sentences translated after it,
    /// the ones relabelling rebuilt, are logged but not counted. They start again from zero.
    mutating func summarize() {
        let (jobs, characters, deepest) = (jobs, characters, deepest)
        let (hits, misses) = (relabel?.hits ?? 0, relabel?.misses ?? 0)
        let took = (Self.percentile(took, 0.5), Self.percentile(took, 0.9))
        let latency = (Self.percentile(latency, 0.5), Self.percentile(latency, 0.9))
        logger.notice(
            "summary jobs=\(jobs) chars=\(characters) took_p50_ms=\(Self.milliseconds(took.0)) took_p90_ms=\(Self.milliseconds(took.1)) latency_p50_ms=\(Self.milliseconds(latency.0)) latency_p90_ms=\(Self.milliseconds(latency.1)) max_depth=\(deepest) relabel_hits=\(hits) relabel_misses=\(misses)"
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

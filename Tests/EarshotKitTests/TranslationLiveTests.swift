import Foundation
import Testing
@preconcurrency import Translation

/// Measures what the live translation pipeline relies on in Apple's Translation framework, on this
/// Mac's installed German → English models. Gated with the live layer; it needs the pair
/// installed but no engine. The figures go to `docs/behaviour.md`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["EARSHOT_LIVE"] == "1"))
struct TranslationLiveTests {
    private static let german = Locale.Language(identifier: "de")
    private static let english = Locale.Language(identifier: "en")
    private static let clock = ContinuousClock()

    /// Near the median sentence of recorded sessions, 70 characters.
    private static let short = [
        "Ich glaube, wir sollten die Lieferung auf nächste Woche verschieben.",
        "Der Umsatz ist im letzten Quartal um zwölf Prozent gestiegen.",
        "Können wir das kurz im nächsten Meeting besprechen, bitte?",
        "Die neue Version läuft seit Montag ohne größere Probleme.",
        "Wir müssen die Zahlen noch einmal mit der Buchhaltung prüfen.",
        "Das Team hat die Schulung für die neuen Kollegen organisiert.",
        "Am Freitag kommt der Architekt und schaut sich das Lager an.",
        "Ich schicke dir die Unterlagen gleich nach dem Termin zu.",
    ]

    /// Near the 90th percentile, 188 characters.
    private static let long = [
        "Wir haben im letzten Quartal zwar deutlich mehr verkauft als geplant, aber die Kosten für die Wartungsverträge sind so stark gestiegen, dass am Ende kaum etwas übrig geblieben ist.",
        "Wenn der Lieferant die Teile nicht bis Ende des Monats schickt, müssen wir die Produktion für mindestens zwei Wochen anhalten und den Kunden erklären, warum sich alles verzögert.",
        "Die Geschäftsführung möchte, dass wir die Daten aus dem alten Lager noch vor Weihnachten übertragen, obwohl eigentlich niemand genau weiß, wer dafür am Ende zuständig ist.",
        "Mein Kollege hat vorgeschlagen, die Schulung auf zwei Tage zu verteilen, damit die neuen Mitarbeiter genug Zeit haben, die Abläufe im Lager und im Büro wirklich kennenzulernen.",
    ]

    private static func session(_ strategy: TranslationSession.Strategy) -> TranslationSession {
        TranslationSession(
            installedSource: german, target: english, preferredStrategy: strategy)
    }

    private static func seconds(_ duration: Duration) -> Double { duration / .seconds(1) }

    private static func timed(_ session: TranslationSession, _ text: String) async throws
        -> (seconds: Double, text: String)
    {
        let start = clock.now
        let text = try await session.translate(text).targetText
        return (seconds(clock.now - start), text)
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(Int((Double(sorted.count - 1) * fraction).rounded()), sorted.count - 1)]
    }

    private static func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }

    /// A session used from two tasks, for the measurements that need that; nothing else touches it.
    private final class Shared: @unchecked Sendable {
        let session: TranslationSession
        init(_ session: TranslationSession) { self.session = session }
    }

    @Test func thePairIsInstalled() async {
        let status = await LanguageAvailability(preferredStrategy: .lowLatency)
            .status(from: Self.german, to: Self.english)
        #expect(status == .installed, "install German → English to run these measurements")
    }

    /// Cold is the first request of a strategy in this process; warm are the requests after it.
    /// The pipeline translates finished sentences with `.lowLatency`, which must stay well within
    /// a second, cold included, for no warm-up to be needed.
    @Test func sentenceLatencyByStrategy() async throws {
        var lowLatency: [Double] = []
        var lowLatencyCold = 0.0
        for (name, strategy) in [
            ("lowLatency", TranslationSession.Strategy.lowLatency), ("highFidelity", .highFidelity),
        ] {
            let session = Self.session(strategy)
            let cold = try await Self.timed(session, "Hallo zusammen.").seconds
            var short: [Double] = []
            var long: [Double] = []
            for _ in 0..<2 {
                for text in Self.short { short.append(try await Self.timed(session, text).seconds) }
                for text in Self.long { long.append(try await Self.timed(session, text).seconds) }
            }
            let all = short + long
            if strategy == .lowLatency { (lowLatency, lowLatencyCold) = (all, cold) }
            print(
                "\(name): cold \(Self.milliseconds(cold)); 70 chars p50 \(Self.milliseconds(Self.percentile(short, 0.5))) max \(Self.milliseconds(short.max() ?? 0)); 188 chars p50 \(Self.milliseconds(Self.percentile(long, 0.5))) max \(Self.milliseconds(long.max() ?? 0)); all p90 \(Self.milliseconds(Self.percentile(all, 0.9)))"
            )
        }
        #expect(Self.percentile(lowLatency, 0.9) <= 1)
        #expect(lowLatencyCold <= 1)
    }

    /// Partials are translated with `.lowLatency`. With finished sentences on `.highFidelity`, a
    /// partial's request would come right after a sentence's: the service runs requests one at a
    /// time, across sessions too, and a request that follows the other strategy's takes some
    /// 300-400 ms more. A partial then waits more than a second, which is why finished sentences
    /// use `.lowLatency` too. If this stops holding, `.highFidelity` is worth measuring again.
    @Test func switchingStrategiesDelaysAPartialOverASecond() async throws {
        let highFidelity = Shared(Self.session(.highFidelity))
        let lowLatency = Self.session(.lowLatency)
        _ = try await Self.timed(highFidelity.session, "Hallo.")
        _ = try await Self.timed(lowLatency, "Hallo.")
        var alone: [Double] = []
        var beside: [Double] = []
        var after: [Double] = []
        var behind: [Double] = []
        for text in Self.short {
            alone.append(try await Self.timed(lowLatency, text).seconds)
        }
        for (index, text) in Self.short.enumerated() {
            let long = Self.long[index % Self.long.count]
            let running = Task { try await Self.timed(highFidelity.session, long).seconds }
            try await Task.sleep(for: .milliseconds(50))
            beside.append(try await Self.timed(lowLatency, text).seconds + 0.05)
            _ = try await running.value
            let queued = Self.clock.now
            _ = try await Self.timed(highFidelity.session, long)
            let partial = try await Self.timed(lowLatency, text).seconds
            after.append(partial)
            behind.append(Self.seconds(Self.clock.now - queued))
        }
        print(
            "lowLatency alone p90 \(Self.milliseconds(Self.percentile(alone, 0.9))), right after highFidelity p90 \(Self.milliseconds(Self.percentile(after, 0.9))); a partial beside a 188-char highFidelity request p90 \(Self.milliseconds(Self.percentile(beside, 0.9))), queued behind it p90 \(Self.milliseconds(Self.percentile(behind, 0.9))) max \(Self.milliseconds(behind.max() ?? 0))"
        )
        #expect(
            Self.percentile(behind, 0.9) > 1,
            "a partial no longer waits over a second: .highFidelity is worth measuring again")
    }

    /// `TranslationSession` is not `Sendable`, and nothing documents concurrent requests on one.
    @Test func twoRequestsAtOnceOnOneSession() async throws {
        let shared = Shared(Self.session(.highFidelity))
        _ = try await Self.timed(shared.session, "Hallo.")
        let (first, second) = (Self.long[0], Self.long[1])
        let one = try await Self.timed(shared.session, first).seconds
        let two = try await Self.timed(shared.session, second).seconds
        let start = Self.clock.now
        async let left = Self.timed(shared.session, first)
        async let right = Self.timed(shared.session, second)
        let (leftResult, rightResult) = try await (left, right)
        let together = Self.seconds(Self.clock.now - start)
        print(
            "one session, one after the other: \(Self.milliseconds(one + two)); at once: \(Self.milliseconds(together)) (each \(Self.milliseconds(leftResult.seconds)), \(Self.milliseconds(rightResult.seconds)))"
        )
        #expect(!leftResult.text.isEmpty && !rightResult.text.isEmpty)
        #expect(together >= 0.9 * (one + two), "the service ran two requests at once")
    }

    /// Nothing documents that cancelling the calling task stops `translate(_:)`. It does not stop
    /// it: the request runs on long after the cancellation and then throws `CancellationError`.
    @Test func cancellingTheCallingTask() async throws {
        let shared = Shared(Self.session(.highFidelity))
        _ = try await Self.timed(shared.session, "Hallo.")
        let text = Self.long.joined(separator: " ")
        let full = try await Self.timed(shared.session, text).seconds
        let start = Self.clock.now
        let request = Task { try await shared.session.translate(text).targetText }
        try await Task.sleep(for: .milliseconds(100))
        request.cancel()
        let result = await request.result
        let took = Self.seconds(Self.clock.now - start)
        let ending: String
        switch result {
        case .success: ending = "finished"
        case .failure(let error): ending = "threw \(type(of: error))"
        }
        print(
            "cancelled after 100 ms: \(ending) after \(Self.milliseconds(took)); uncancelled \(Self.milliseconds(full))"
        )
        #expect(ending == "threw CancellationError")
        #expect(took >= 0.5 * full, "cancelling the task stopped the request early")
    }

    /// About the longest paragraph of a recorded monologue.
    @Test func aFourThousandCharacterParagraph() async throws {
        let session = Self.session(.highFidelity)
        _ = try await Self.timed(session, "Hallo.")
        var sentences: [String] = []
        var index = 0
        while sentences.joined(separator: " ").count < 4000 {
            let pool = index.isMultiple(of: 3) ? Self.long : Self.short
            sentences.append(pool[index % pool.count])
            index += 1
        }
        let paragraph = sentences.joined(separator: " ")
        let result = try await Self.timed(session, paragraph)
        let out = result.text.split(whereSeparator: { ".?!".contains($0) }).count
        print(
            "highFidelity, \(paragraph.count) chars in \(sentences.count) sentences: \(Self.milliseconds(result.seconds)), \(out) sentences back"
        )
        #expect(out >= sentences.count - 1)
    }
}

import Foundation
import Testing

@testable import EarshotKit

@Suite struct TranslationQueueTests {
    private func sentence(_ text: String) -> SentenceRequest {
        SentenceRequest(text: text, paragraph: text)
    }

    /// Words in flight wait for at most the sentence being translated, and a speaker who never
    /// pauses still gets their sentences translated.
    @Test func wordsInFlightAndSentencesTakeTurns() {
        var queue = TranslationQueue()
        queue.demand([sentence("Eins."), sentence("Zwei.")], at: 0)
        #expect(queue.next()?.job == .sentence(sentence("Eins.")))
        queue.live("Dr", on: .system, at: 0.1)
        queue.live("Drei", on: .system, at: 0.2)
        #expect(queue.next() == nil)
        queue.finish()
        #expect(queue.next() == .init(job: .live("Drei", on: .system), queuedAt: 0.1))
        queue.finish()
        queue.live("Drei und", on: .system, at: 0.3)
        #expect(queue.next()?.job == .sentence(sentence("Zwei.")))
        queue.finish()
        #expect(queue.next()?.job == .live("Drei und", on: .system))
        queue.finish()
        #expect(queue.next() == nil)
    }

    /// A refinement rewrote the second sentence before its turn: the old text is never sent.
    @Test func aSentenceRewrittenBeforeItsTurnIsNeverSent() {
        var queue = TranslationQueue()
        queue.demand([sentence("Eins."), sentence("Zwie.")], at: 0)
        #expect(queue.next()?.job == .sentence(sentence("Eins.")))
        queue.demand([sentence("Eins."), sentence("Zwei.")], at: 0.5)
        #expect(queue.depth == 1)
        queue.finish()
        #expect(queue.next() == .init(job: .sentence(sentence("Zwei.")), queuedAt: 0.5))
    }

    /// The paragraph grew while its sentence was being translated: the sentence is not sent again.
    @Test func theSentenceBeingTranslatedIsNotAskedForAgain() {
        var queue = TranslationQueue()
        queue.demand([SentenceRequest(text: "Eins.", paragraph: "Eins.")], at: 0)
        #expect(queue.next() != nil)
        queue.demand(
            [
                SentenceRequest(text: "Eins.", paragraph: "Eins. Zwei."),
                SentenceRequest(text: "Zwei.", paragraph: "Eins. Zwei."),
            ], at: 1)
        #expect(queue.depth == 1)
        queue.finish()
        #expect(
            queue.next()?.job == .sentence(SentenceRequest(text: "Zwei.", paragraph: "Eins. Zwei."))
        )
    }

    /// A sentence still waiting when the queue is asked again keeps the time it was first asked
    /// for, so its wait counts from the final that made it.
    @Test func aWaitingSentenceKeepsItsFirstTime() {
        var queue = TranslationQueue()
        queue.demand([sentence("Eins.")], at: 0)
        #expect(queue.next() != nil)
        queue.demand([sentence("Zwei.")], at: 1)
        queue.demand([sentence("Zwei."), sentence("Drei.")], at: 2)
        queue.finish()
        #expect(queue.next() == .init(job: .sentence(sentence("Zwei.")), queuedAt: 1))
        queue.finish()
        #expect(queue.next() == .init(job: .sentence(sentence("Drei.")), queuedAt: 2))
    }

    /// Words that became final are no longer translated as words in flight.
    @Test func finishedWordsLeaveTheQueue() {
        var queue = TranslationQueue()
        queue.live("Hallo", on: .microphone, at: 0)
        queue.live(nil, on: .microphone, at: 0.1)
        #expect(queue.next() == nil)
    }
}

/// A slow speaker's monologue: 24 characters a second, one paragraph, cut into a final every
/// 3 s whatever the sentences, so finals end mid-sentence; each final refined 0.5 s later with its
/// last word heard differently, and the words in flight changing every quarter second.
private enum MonologueEvent {
    case partial(Double, String)
    case final(Double, [Word])
    case refine(Double, Int, [Word])

    var time: Double {
        switch self {
        case .partial(let time, _), .final(let time, _), .refine(let time, _, _): time
        }
    }

    private static let sentences = [
        "Ich glaube, wir sollten die Lieferung auf nächste Woche verschieben.",
        "Der Umsatz ist im letzten Quartal um zwölf Prozent gestiegen.",
        "Wir haben im letzten Quartal zwar deutlich mehr verkauft als geplant, aber die Kosten für die Wartungsverträge sind so stark gestiegen, dass am Ende kaum etwas übrig geblieben ist.",
        "Können wir das kurz im nächsten Meeting besprechen, bitte?",
        "Die neue Version läuft seit Montag ohne größere Probleme.",
        "Wenn der Lieferant die Teile nicht bis Ende des Monats schickt, müssen wir die Produktion für mindestens zwei Wochen anhalten und den Kunden erklären, warum sich alles verzögert.",
        "Wir müssen die Zahlen noch einmal mit der Buchhaltung prüfen.",
        "Am Freitag kommt der Architekt und schaut sich das Lager an.",
    ]

    static func script(seconds: Double) -> [MonologueEvent] {
        let (speed, every) = (24.0, 3.0)
        var words: [Word] = []
        var time = 0.0
        for index in 0... {
            guard time < seconds else { break }
            for text in sentences[index % sentences.count].split(separator: " ") {
                let length = Double(text.count + 1) / speed
                words.append(Word(word: String(text), start: time, end: time + length, speaker: 1))
                time += length
            }
        }
        var events: [MonologueEvent] = []
        for (index, cut) in stride(from: every, through: seconds, by: every).enumerated() {
            let final = words.filter { $0.end <= cut && $0.end > cut - every }
            for step in stride(from: cut - every + 0.25, to: cut, by: 0.25) {
                let spoken = final.filter { $0.end <= step }.map(\.word).joined(separator: " ")
                if !spoken.isEmpty { events.append(.partial(step, spoken)) }
            }
            events.append(.final(cut, final))
            var refined = final
            let last = refined.removeLast()
            refined.append(
                Word(word: last.word + "e", start: last.start, end: last.end, speaker: 1))
            events.append(.refine(cut + 0.5, index, refined))
        }
        return events.sorted { $0.time < $1.time }
    }
}

/// The app's worker on a simulated clock with a fake translator: after every change the
/// transcript's pending sentences are demanded, and one job runs at a time.
private struct Simulation {
    var requested: [String: Int] = [:]
    var requestedCharacters = 0
    var spokenCharacters = 0
    /// For each final, how long until the paragraph's translated sentences reached its last word.
    var coverLatencies: [Double] = []
    var deepest = 0
    /// Times the queue held more than the sentences of the last two finals.
    var depthOverBound = 0
    /// The most sentence jobs any live job waited for.
    var liveWaitedFor = 0
    var liveJobs = 0
    /// The share of the time the translator was working.
    var busy: Double { busyTime / duration }

    private let latency: (String) -> Double
    private var transcript = Transcript()
    private var queue = TranslationQueue()
    private var applied: [AppliedFinal] = []
    private var finals: [(time: Double, text: String)] = []
    private var running: (started: TranslationQueue.Started, until: Double)?
    private var sentenceJobs: [(start: Double, end: Double)] = []
    private var busyTime = 0.0
    private var duration = 0.0

    init(seconds: Double, latency: @escaping (String) -> Double) {
        self.latency = latency
        transcript.translate(into: "en")
        var events = MonologueEvent.script(seconds: seconds)[...]
        while running != nil || !events.isEmpty {
            if let job = running, events.first.map({ job.until <= $0.time }) ?? true {
                finish(job.started, at: job.until)
            } else if let event = events.popFirst() {
                apply(event)
                start(at: event.time)
            }
        }
    }

    private mutating func apply(_ event: MonologueEvent) {
        switch event {
        case .partial(let time, let words):
            let current = transcript.partials[.system] ?? ""
            transcript.applyPartial(String(words.dropFirst(current.count)), on: .system)
            queue.live(transcript.partials[.system], on: .system, at: time)
        case .final(let time, let words):
            applied.append(transcript.applyFinal(transcript: "", words: words, on: .system))
            finals.append((time, words.map(\.word).joined(separator: " ")))
            spokenCharacters += finals[finals.count - 1].text.count
            refresh(at: time)
        case .refine(let time, let index, let words):
            transcript.refine(applied[index], with: words)
            refresh(at: time)
        }
    }

    private mutating func refresh(at time: Double) {
        if transcript.partials[.system] == nil { queue.live(nil, on: .system, at: time) }
        queue.demand(transcript.pendingSentences, at: time)
        deepest = max(deepest, queue.depth)
        let lastTwo = finals.suffix(2).map(\.text).joined(separator: " ")
        if queue.depth > Sentences.split(lastTwo).count + 1 { depthOverBound += 1 }
        cover(at: time)
    }

    /// The paragraph's text is its sentences, and its finals' segments, each joined by a space:
    /// a final is covered once the sentences translated in order reach its last character.
    private mutating func cover(at time: Double) {
        guard let paragraph = transcript.utterances.first else { return }
        let translated = paragraph.sentences.prefix { transcript.outcomes[$0] != nil }
        let reached = translated.map(\.count).reduce(0, +) + max(translated.count - 1, 0)
        var end = -1
        for (index, segment) in paragraph.segments.enumerated() {
            end += segment.text.count + 1
            guard index == coverLatencies.count else { continue }
            guard end <= reached else { return }
            coverLatencies.append(time - finals[index].time)
        }
    }

    private mutating func start(at time: Double) {
        guard running == nil, let started = queue.next() else { return }
        let text: String
        switch started.job {
        case .sentence(let request):
            text = request.text
            requested[text, default: 0] += 1
            requestedCharacters += text.count
            sentenceJobs.append((time, time + latency(text)))
        case .live(let words, _):
            text = words
            liveJobs += 1
            let waitedFor = sentenceJobs.filter { $0.end > started.queuedAt && $0.start < time }
            liveWaitedFor = max(liveWaitedFor, waitedFor.count)
        }
        busyTime += latency(text)
        running = (started, time + latency(text))
    }

    private mutating func finish(_ started: TranslationQueue.Started, at time: Double) {
        running = nil
        duration = time
        queue.finish()
        switch started.job {
        case .sentence(let request):
            transcript.record(.translated("EN " + request.text), for: request.text, into: "en")
            refresh(at: time)
        case .live(let words, let channel):
            transcript.setLiveTranslation(
                Translation(sourceText: words, text: "EN " + words), on: channel)
        }
        start(at: time)
    }
}

@Suite struct TranslationSimulationTests {
    /// Seconds a request takes with `.lowLatency`, the strategy the app uses: 20 ms plus 0.4 ms
    /// a character fits its measured 21-63 ms for 70 characters and 44-97 ms for 188
    /// (docs/behaviour.md).
    private static func lowLatency(_ text: String) -> Double { 0.02 + 0.0004 * Double(text.count) }

    /// Seven times slower, so the queue always has a backlog to hold: the translator is busy
    /// nearly all the time.
    private static func loaded(_ text: String) -> Double { 7 * lowLatency(text) }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[Int((Double(sorted.count - 1) * fraction).rounded())]
    }

    /// Two minutes of it: 40 finals 3 s apart. Each final's words are translated within a
    /// second, and the work grows with what is said.
    @Test func aSlowMonologueIsTranslatedWithinASecondOfEachFinal() {
        let run = Simulation(seconds: 120, latency: Self.lowLatency)
        let longer = Simulation(seconds: 240, latency: Self.lowLatency)
        #expect(run.coverLatencies.count == 40)
        #expect(run.requested.values.allSatisfy { $0 == 1 })
        #expect(run.requestedCharacters <= 3 * run.spokenCharacters)
        #expect(Double(longer.requestedCharacters) <= 2.2 * Double(run.requestedCharacters))
        #expect(Self.percentile(run.coverLatencies, 0.9) <= 1)
        #expect((run.coverLatencies.max() ?? .infinity) <= 2)
    }

    /// With the translator saturated, what waits stays within the last two finals' sentences and
    /// does not grow with the length; words in flight wait for one sentence at most, and
    /// sentences still get their turn between them.
    @Test func theBacklogStaysBoundedUnderLoad() {
        let run = Simulation(seconds: 120, latency: Self.loaded)
        let longer = Simulation(seconds: 240, latency: Self.loaded)
        #expect(run.busy > 0.9)
        #expect(longer.coverLatencies.count == 80)
        #expect(longer.requested.values.allSatisfy { $0 == 1 })
        #expect((longer.coverLatencies.max() ?? .infinity) <= 2)
        #expect(run.depthOverBound == 0 && longer.depthOverBound == 0)
        #expect(longer.deepest <= run.deepest + 1)
        #expect(run.liveJobs > 0 && run.liveWaitedFor <= 1 && longer.liveWaitedFor <= 1)
    }
}

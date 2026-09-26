import Foundation

/// What waits for the translator, one request at a time. Apple's service runs requests one after
/// the other anyway, across sessions too, so sending more at once only makes each wait longer
/// (docs/behaviour.md, Apple Translation). Times are seconds on any clock that only goes forward.
public struct TranslationQueue: Sendable {
    public enum Job: Sendable, Equatable {
        case sentence(SentenceRequest)
        /// A channel's words in flight, as they were when the job started.
        case live(String, on: Channel)
    }

    /// A job as it starts, with when it was first asked for.
    public struct Started: Sendable, Equatable {
        public let job: Job
        public let queuedAt: Double
    }

    private var sentences: [SentenceRequest] = []
    private var queuedAt: [String: Double] = [:]
    private var live: [Channel: (text: String, since: Double)] = [:]
    private var running: Job?
    private var lastWasLive = false

    public init() {}

    /// Sentences waiting, not counting the one being translated.
    public var depth: Int { sentences.count }

    /// Replaces what waits with what the transcript lacks now, so a sentence a refinement or a
    /// relabel rewrote before its turn is never sent. A sentence keeps the time it was first asked
    /// for while it keeps waiting.
    public mutating func demand(_ requests: [SentenceRequest], at time: Double) {
        var translating: String?
        if case .sentence(let request) = running { translating = request.text }
        sentences = requests.filter { $0.text != translating }
        queuedAt = Dictionary(
            sentences.map { ($0.text, queuedAt[$0.text] ?? time) },
            uniquingKeysWith: { old, _ in old })
    }

    /// A channel's words in flight; only the latest waits. Nil once they are final.
    public mutating func live(_ text: String?, on channel: Channel, at time: Double) {
        guard let text, !text.isEmpty else {
            live[channel] = nil
            return
        }
        live[channel] = (text, live[channel]?.since ?? time)
    }

    /// The next job, or nil while one runs or nothing waits. Words in flight and finished
    /// sentences take turns when both wait: the words never wait for more than one sentence, and a
    /// speaker who never pauses still gets their sentences translated.
    public mutating func next() -> Started? {
        guard running == nil else { return nil }
        let waiting = live.min { $0.value.since < $1.value.since }
        let started: Started
        if let waiting, sentences.isEmpty || !lastWasLive {
            live[waiting.key] = nil
            started = Started(
                job: .live(waiting.value.text, on: waiting.key), queuedAt: waiting.value.since)
            lastWasLive = true
        } else if !sentences.isEmpty {
            let sentence = sentences.removeFirst()
            started = Started(
                job: .sentence(sentence), queuedAt: queuedAt.removeValue(forKey: sentence.text) ?? 0
            )
            lastWasLive = false
        } else {
            return nil
        }
        running = started.job
        return started
    }

    public mutating func finish() {
        running = nil
    }
}

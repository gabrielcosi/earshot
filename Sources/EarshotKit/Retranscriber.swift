import Foundation

/// What a second pass heard in a clip.
public struct Retranscription: Sendable, Equatable {
    public let words: [Word]
    /// The language `auto` heard when it is none of the spoken ones and the spoken language's
    /// words that read best do not read as it, so the speech is in another language. The words
    /// are then `auto`'s: forced into a spoken language, they come out garbled or empty.
    public let heard: String?

    public init(words: [Word], heard: String? = nil) {
        self.words = words
        self.heard = heard
    }
}

/// A speaker turn with the words heard in its audio alone, timed from the session's start.
public struct TranscribedTurn: Sendable, Equatable {
    public let turn: SpeakerTurn
    public let words: [Word]
    /// As `Retranscription.heard`.
    public let heard: String?

    public init(turn: SpeakerTurn, words: [Word], heard: String? = nil) {
        self.turn = turn
        self.words = words
        self.heard = heard
    }
}

/// A second, whole-utterance pass over audio the live stream already transcribed, through the
/// engine's HTTP endpoint. Each request starts a fresh decoder, so a language switch at the start
/// of the utterance is recognized from its first word.
public enum Retranscriber {
    /// Transcribes in the configured languages only: pinned when there is one, otherwise `auto`,
    /// redone in each configured language when `auto` strays outside them.
    public static func transcribe(
        pcm: Data, engine: EngineEndpoint, allowed: [String], contexts: [SpeechContext] = []
    ) async throws -> Retranscription {
        if allowed.count == 1 {
            return Retranscription(
                words: try await transcribe(
                    pcm: pcm, engine: engine, language: allowed[0], contexts: contexts
                ).words)
        }
        let first = try await transcribe(
            pcm: pcm, engine: engine, language: Languages.auto, contexts: contexts)
        if LanguagePolicy.accepts(first.words, reported: first.language, allowed: allowed) {
            return Retranscription(words: first.words)
        }
        let candidates = try await withThrowingTaskGroup(of: (String, [Word]).self) { group in
            for language in allowed {
                group.addTask {
                    (
                        language,
                        try await transcribe(
                            pcm: pcm, engine: engine, language: language, contexts: contexts
                        ).words
                    )
                }
            }
            return try await group.reduce(into: [(language: String, words: [Word])]()) {
                $0.append((language: $1.0, words: $1.1))
            }
        }
        let best = LanguagePolicy.best(of: candidates)
        let heard = LanguagePolicy.heard(
            first.language, allowed: allowed, said: first.words, redo: best)
        return Retranscription(
            words: heard == nil ? best?.words ?? first.words : first.words, heard: heard)
    }

    /// Each turn transcribed from its own audio, so its words are the turn's speaker's. One
    /// request at a time: the engine serializes decoding anyway.
    public static func transcribe(
        turns: [SpeakerTurn], pcm: Data, engine: EngineEndpoint, allowed: [String],
        contexts: [SpeechContext] = []
    ) async throws -> [TranscribedTurn] {
        var transcribed: [TranscribedTurn] = []
        for turn in turns {
            let result = try await transcribe(
                pcm: PCM.slice(pcm, from: turn.start, to: turn.end), engine: engine,
                allowed: allowed, contexts: contexts)
            transcribed.append(
                TranscribedTurn(
                    turn: turn,
                    words: result.words.map {
                        Word(
                            word: $0.word, start: $0.start + turn.start, end: $0.end + turn.start,
                            speaker: turn.speaker)
                    }, heard: result.heard))
        }
        return transcribed
    }

    static func transcribe(
        pcm: Data, engine: EngineEndpoint, language: String, contexts: [SpeechContext]
    ) async throws -> (
        words: [Word], language: String?
    ) {
        var base = engine.request("v1/audio/transcriptions")
        base.timeoutInterval = EngineEndpoint.timeout(
            forAudioSeconds: Double(pcm.count) / Double(PCM.bytesPerSecond))
        let (request, body) = Multipart.request(
            base, fields: fields(language: language, contexts: contexts), wav: PCM.wav(pcm))
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        return try heard(in: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func heard(in data: Data, status: Int) throws -> (words: [Word], language: String?) {
        let decoded = try JSONDecoder().decode(
            Response.self, from: EngineEndpoint.answer(data, status: status))
        return (decoded.words ?? [], decoded.language)
    }

    private static func fields(language: String, contexts: [SpeechContext]) -> [String: String] {
        var fields = ["response_format": "verbose_json", "language": language]
        if !contexts.isEmpty, let json = try? JSONEncoder().encode(contexts) {
            fields["speech_contexts"] = String(bytes: json, encoding: .utf8)
        }
        return fields
    }

    private struct Response: Decodable {
        let words: [Word]?
        let language: String?
    }
}

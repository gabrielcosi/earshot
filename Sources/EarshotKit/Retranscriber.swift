import Foundation

/// A second, whole-utterance pass over audio the live stream already transcribed, through the
/// engine's HTTP endpoint. Each request starts a fresh decoder, so a language switch at the start
/// of the utterance is recognized from its first word.
public enum Retranscriber {
    /// Transcribes in the configured languages only: pinned when there is one, otherwise `auto`,
    /// redone in each configured language when `auto` strays outside them.
    public static func transcribe(
        pcm: Data, engine: EngineEndpoint, allowed: [String], contexts: [SpeechContext] = []
    ) async throws -> [Word] {
        if allowed.count == 1 {
            return try await transcribe(
                pcm: pcm, engine: engine, language: allowed[0], contexts: contexts
            ).words
        }
        let first = try await transcribe(
            pcm: pcm, engine: engine, language: Languages.auto, contexts: contexts)
        if LanguagePolicy.accepts(first.words, reported: first.language, allowed: allowed) {
            return first.words
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
        return LanguagePolicy.best(of: candidates)?.words ?? first.words
    }

    /// Each turn transcribed from its own audio, so its words are the turn's speaker's. One
    /// request at a time: the engine serializes decoding anyway.
    public static func transcribe(
        turns: [SpeakerTurn], pcm: Data, engine: EngineEndpoint, allowed: [String],
        contexts: [SpeechContext] = []
    ) async throws -> [TranscribedTurn] {
        var transcribed: [TranscribedTurn] = []
        for turn in turns {
            let words = try await transcribe(
                pcm: PCM.slice(pcm, from: turn.start, to: turn.end), engine: engine,
                allowed: allowed, contexts: contexts)
            transcribed.append(
                TranscribedTurn(
                    turn: turn,
                    words: words.map {
                        Word(
                            word: $0.word, start: $0.start + turn.start, end: $0.end + turn.start,
                            speaker: turn.speaker)
                    }))
        }
        return transcribed
    }

    static func transcribe(
        pcm: Data, engine: EngineEndpoint, language: String, contexts: [SpeechContext]
    ) async throws -> (
        words: [Word], language: String?
    ) {
        let request = Multipart.request(
            engine.request("v1/audio/transcriptions"),
            fields: fields(language: language, contexts: contexts), wav: PCM.wav(pcm))
        let (data, response) = try await URLSession.shared.upload(for: request.0, from: request.1)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return ([], nil) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
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

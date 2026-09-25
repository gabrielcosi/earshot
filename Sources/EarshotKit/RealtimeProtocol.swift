import Foundation

/// Client-side settings sent once, before any audio, as a `session.update` event.
public struct SessionSettings: Encodable, Sendable, Equatable {
    public var sampleRate: Int
    public var wordTimestamps: Bool
    public var speakerDiarization: Bool
    public var language: String?
    public var speechContexts: [SpeechContext]?

    public init(
        sampleRate: Int = 16_000,
        wordTimestamps: Bool = true,
        speakerDiarization: Bool,
        language: String? = nil,
        speechContexts: [SpeechContext]? = nil
    ) {
        self.sampleRate = sampleRate
        self.wordTimestamps = wordTimestamps
        self.speakerDiarization = speakerDiarization
        self.language = language
        self.speechContexts = speechContexts?.isEmpty == true ? nil : speechContexts
    }

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case wordTimestamps = "word_timestamps"
        case speakerDiarization = "speaker_diarization"
        case language
        case speechContexts = "speech_contexts"
    }
}

/// Phrases the engine should favour while decoding, and how strongly.
public struct SpeechContext: Codable, Sendable, Equatable {
    public let phrases: [String]
    public let boost: Double

    public init(phrases: [String], boost: Double) {
        self.phrases = phrases
        self.boost = boost
    }
}

enum ClientEvent: Sendable {
    case sessionUpdate(SessionSettings)
    case commit

    func encoded() throws -> String {
        let payload: any Encodable =
            switch self {
            case .sessionUpdate(let settings):
                SessionUpdate(session: settings)
            case .commit:
                TypeOnly(type: "input_audio_buffer.commit")
            }
        let data = try JSONEncoder().encode(payload)
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private struct SessionUpdate: Encodable {
        let type = "session.update"
        let session: SessionSettings
    }

    private struct TypeOnly: Encodable {
        let type: String
    }
}

public struct Word: Decodable, Sendable, Equatable {
    public let word: String
    public let start: Double
    public let end: Double
    /// 1-based Sortformer speaker slot, in order of first appearance; absent without diarization.
    public let speaker: Int?

    public init(word: String, start: Double, end: Double, speaker: Int? = nil) {
        self.word = word
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

public enum ServerEvent: Sendable, Equatable {
    case sessionCreated(sampleRate: Int, model: String)
    case partial(delta: String)
    case final(transcript: String, words: [Word])
    case committed
    /// An error the engine reported; the stream stays open.
    case error(String)
    /// The socket failed or closed; the stream ends after this.
    case disconnected(String)
    case other(String)

    public static func decode(_ text: String) throws -> ServerEvent {
        let raw = try JSONDecoder().decode(Raw.self, from: Data(text.utf8))
        switch raw.type {
        case "session.created":
            return .sessionCreated(
                sampleRate: raw.session?.sampleRate ?? 16_000,
                model: raw.session?.model ?? ""
            )
        case "conversation.item.input_audio_transcription.delta":
            return .partial(delta: raw.delta ?? "")
        case "conversation.item.input_audio_transcription.completed":
            return .final(transcript: raw.transcript ?? "", words: raw.words ?? [])
        case "input_audio_buffer.committed":
            return .committed
        case "error":
            return .error(raw.error?.message ?? "unknown server error")
        default:
            return .other(raw.type)
        }
    }

    private struct Raw: Decodable {
        let type: String
        let delta: String?
        let transcript: String?
        let words: [Word]?
        let session: RawSession?
        let error: ErrorBody?
    }

    private struct ErrorBody: Decodable {
        let message: String?
    }
}

private struct RawSession: Decodable {
    let sampleRate: Int?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case model
    }
}

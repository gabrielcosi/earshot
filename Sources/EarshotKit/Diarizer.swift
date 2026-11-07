import Foundation

/// Speaker turns for a whole recording, from the engine's diarizer.
public enum Diarizer {
    /// Full attention over the whole recording holds 5,000 encoder frames of 80 ms, about 6.6
    /// minutes (`pos_emb_max_len` in the engine's diarizer); longer audio makes it fail.
    public static let offlineLimit = 5_000 * 0.08

    /// The engine's error, as it answered the request.
    enum Failure: Error {
        case http(Int, String)
    }

    /// Full attention places turns best. Past its limit, the streaming diarizer covers the whole
    /// recording, with the model's long-chunk geometry rather than the live stream's
    /// low-latency one, which is many times slower (docs/behaviour.md, Engine: diarization).
    static func fields(forSeconds seconds: Double) -> [String: String] {
        seconds <= offlineLimit
            ? ["mode": "offline"] : ["mode": "streaming", "geometry": "offline"]
    }

    public static func diarize(pcm: Data, engine: EngineEndpoint) async throws -> [SpeakerTurn] {
        let seconds = Double(pcm.count) / Double(PCM.bytesPerSecond)
        var base = engine.request("v1/audio/diarizations")
        base.timeoutInterval = EngineEndpoint.timeout(forAudioSeconds: seconds)
        let (request, body) = Multipart.request(
            base, fields: fields(forSeconds: seconds), wav: PCM.wav(pcm))
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        return try turns(in: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func turns(in data: Data, status: Int) throws -> [SpeakerTurn] {
        guard status == 200 else {
            throw Failure.http(status, String(bytes: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(Response.self, from: data).segments
    }

    private struct Response: Decodable {
        let segments: [SpeakerTurn]
    }
}

import Foundation

/// Speaker turns for a whole recording, from the engine's diarizer.
public enum Diarizer {
    /// Full attention over the whole recording holds 5,000 encoder frames of 80 ms, about 6.6
    /// minutes (`pos_emb_max_len` in the engine's diarizer); longer audio makes it fail.
    public static let offlineLimit = 5_000 * 0.08

    /// Full attention places turns best; past its limit the engine's streaming diarizer, meant
    /// for long-form audio, covers the whole recording instead.
    public static func mode(forSeconds seconds: Double) -> String {
        seconds <= offlineLimit ? "offline" : "streaming"
    }

    public static func diarize(pcm: Data, engine: EngineEndpoint) async throws -> [SpeakerTurn] {
        let (request, body) = Multipart.request(
            engine.request("v1/audio/diarizations"),
            fields: ["mode": mode(forSeconds: Double(pcm.count) / Double(PCM.bytesPerSecond))],
            wav: PCM.wav(pcm))
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return try JSONDecoder().decode(Response.self, from: data).segments
    }

    private struct Response: Decodable {
        let segments: [SpeakerTurn]
    }
}

import Foundation

/// Where the engine listens and the bearer key its API routes require. The key is nil for an
/// engine started without one (`mise run serve`), which ignores the header.
public struct EngineEndpoint: Sendable {
    public let url: URL
    public let apiKey: String?

    public init(url: URL, apiKey: String? = nil) {
        self.url = url
        self.apiKey = apiKey
    }

    func request(_ path: String, scheme: String? = nil) -> URLRequest {
        var components = URLComponents(
            url: url.appending(path: path), resolvingAgainstBaseURL: false)
        if let scheme { components?.scheme = scheme }
        var request = URLRequest(url: components?.url ?? url)
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return request
    }
}

extension EngineEndpoint {
    /// The engine refused an HTTP request, with its status and answer.
    enum Failure: Error {
        case http(Int, String)
    }

    /// The answer to an HTTP request, or the engine's refusal as an error.
    static func answer(_ data: Data, status: Int) throws -> Data {
        guard status == 200 else {
            throw Failure.http(status, String(bytes: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// For a request over a recording. The engine answers only once it is done, and URLSession
    /// gives up after 60 s without a byte (its default `timeoutIntervalForRequest`), which a
    /// 43-minute diarization once outlasted at 81 s. A quarter of the audio's length is ample
    /// for the engine's slowest pass and still ends a request to an engine that has hung.
    static func timeout(forAudioSeconds seconds: Double) -> TimeInterval {
        max(60, seconds / 4)
    }
}

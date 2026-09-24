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

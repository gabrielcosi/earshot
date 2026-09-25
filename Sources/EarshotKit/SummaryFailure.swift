import Foundation

/// Why a summary failed, in words the user can act on. Anything not listed goes to the log only:
/// raw error text stays out of the interface.
public enum SummaryFailure: Hashable, Sendable {
    case unreachable
    /// Requests allow 300–600 s, so this is a slow server rather than an unreachable one.
    case timedOut
    case keyRefused
    case serviceError
    case appleIntelligenceUnavailable

    /// The cause of an endpoint's error, or nil when it is not one of these.
    public init?(_ error: any Error) {
        let status: Int
        switch error {
        case let error as URLError:
            if error.code == .timedOut {
                self = .timedOut
                return
            }
            guard Self.unreachableCodes.contains(error.code) else { return nil }
            self = .unreachable
            return
        case OpenAIChat.Failure.http(let code, _): status = code
        case AnthropicMessages.Failure.http(let code, _): status = code
        default: return nil
        }
        self = [401, 403].contains(status) ? .keyRefused : .serviceError
    }

    public var message: String {
        switch self {
        case .unreachable: "Earshot could not reach the summary address."
        case .timedOut: "The summary service did not answer in time."
        case .keyRefused: "The summary service refused the API key."
        case .serviceError: "The summary service returned an error."
        case .appleIntelligenceUnavailable: "Apple Intelligence is not available on this Mac."
        }
    }

    /// Offline, or no route to the host.
    private static let unreachableCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
        .networkConnectionLost,
    ]
}

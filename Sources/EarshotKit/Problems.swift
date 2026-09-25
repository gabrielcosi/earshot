import Foundation

/// Something that keeps Earshot from working as the user expects, shown until it is resolved or
/// the session it belongs to is over.
public enum Problem: Hashable, Sendable, Identifiable {
    case noModel
    case microphoneDenied
    /// This and the other failures with a detail show it after the message, so it holds only what
    /// the user can act on, such as a full disk, or nothing; everything else goes to the log.
    case captureFailed(String)
    /// The engine did not start.
    case engineFailed(String)
    /// The engine binary is not in the app bundle.
    case engineMissing
    /// The engine exited during a session.
    case engineStopped
    /// A channel's stream closed under a session; the session ends with it.
    case connectionLost(Channel)
    /// An error the engine sent on a stream that stays open; the session continues.
    case engineError(Channel)
    case savingFailed(String)
    /// The Markdown copy could not be written; the transcript itself is saved.
    case exportFailed(String)
    case audioNotKept(String)
    /// Export Audio… could not write the copy; the kept audio is as it was.
    case audioNotExported(String)
    /// With its cause, when it is one the user can act on.
    case summaryFailed(SummaryFailure?)
    /// Language identifiers, such as "de" and "en".
    case translationNeedsDownload(from: String, to: String)
    case translationUnsupported(from: String, to: String)

    /// One per kind, and per channel or language pair where there is one, so a problem reported
    /// again replaces its earlier report.
    public var id: String {
        switch self {
        case .noModel: "noModel"
        case .microphoneDenied: "microphoneDenied"
        case .captureFailed: "captureFailed"
        case .engineFailed: "engineFailed"
        case .engineMissing: "engineMissing"
        case .engineStopped: "engineStopped"
        case .connectionLost(let channel): "connectionLost.\(channel.rawValue)"
        case .engineError(let channel): "engineError.\(channel.rawValue)"
        case .savingFailed: "savingFailed"
        case .exportFailed: "exportFailed"
        case .audioNotKept: "audioNotKept"
        case .audioNotExported: "audioNotExported"
        case .summaryFailed: "summaryFailed"
        case .translationNeedsDownload(let source, let target):
            "translationNeedsDownload.\(source).\(target)"
        case .translationUnsupported(let source, let target):
            "translationUnsupported.\(source).\(target)"
        }
    }

    public var isTranslation: Bool {
        switch self {
        case .translationNeedsDownload, .translationUnsupported: true
        default: false
        }
    }

    /// Whether a new session makes it moot. The rest stand until what causes them changes.
    public var endsWithSession: Bool {
        switch self {
        case .noModel, .translationNeedsDownload, .translationUnsupported: false
        default: true
        }
    }

    public func message(in locale: Locale = .current) -> String {
        switch self {
        case .noModel:
            "Earshot needs a transcription model before it can listen."
        case .microphoneDenied:
            "Earshot is not allowed to use the microphone."
        case .captureFailed(let detail):
            Self.sentences("Earshot could not capture audio.", detail)
        case .engineFailed(let detail):
            Self.sentences("The speech engine did not start.", detail)
        case .engineMissing:
            "The speech engine is missing from Earshot. Reinstall Earshot."
        case .engineStopped:
            "The speech engine stopped during the session. What was transcribed so far is saved."
        case .connectionLost(let channel):
            "Earshot lost its connection to the speech engine while transcribing \(Self.name(channel)), so the session ended. What was transcribed so far is saved."
        case .engineError(let channel):
            "The speech engine hit a problem while transcribing \(Self.name(channel))."
        case .savingFailed(let detail):
            Self.sentences("Earshot could not save the transcript.", detail)
        case .exportFailed(let detail):
            Self.sentences("Earshot could not write the transcript's Markdown file.", detail)
        case .audioNotKept(let detail):
            Self.sentences("Earshot could not save the audio.", detail)
        case .audioNotExported(let detail):
            Self.sentences("Earshot could not export the audio.", detail)
        case .summaryFailed(let cause):
            Self.sentences("Earshot could not summarize the transcript.", cause?.message ?? "")
        case .translationNeedsDownload(let source, let target):
            "Translating \(Self.name(source, in: locale)) into \(Self.name(target, in: locale)) needs Apple's language download."
        case .translationUnsupported(let source, let target):
            "Apple cannot translate \(Self.name(source, in: locale)) into \(Self.name(target, in: locale))."
        }
    }

    private static func sentences(_ message: String, _ detail: String) -> String {
        detail.isEmpty ? message : "\(message) \(detail)"
    }

    private static func name(_ channel: Channel) -> String {
        switch channel {
        case .microphone: "your microphone"
        case .system: "the Mac's audio"
        }
    }

    private static func name(_ language: String, in locale: Locale) -> String {
        locale.localizedString(forLanguageCode: language) ?? language
    }
}

/// The problems standing now, in the order they were first reported.
public struct Problems: Sendable, Equatable {
    public private(set) var all: [Problem] = []

    public init() {}

    public mutating func report(_ problem: Problem) {
        if let index = all.firstIndex(where: { $0.id == problem.id }) {
            all[index] = problem
        } else {
            all.append(problem)
        }
    }

    public mutating func resolve(where matches: (Problem) -> Bool) {
        all.removeAll(where: matches)
    }

    /// The user closed it; it comes back when it is reported again.
    public mutating func dismiss(_ problem: Problem) {
        resolve { $0.id == problem.id }
    }

    public mutating func startSession() {
        resolve { $0.endsWithSession }
    }
}

/// The first-run setup's pages, in order.
public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome
    case models
    case permissions
    case listening
    case languages
    case transcripts
    case captions
    case ready
}

/// Where setup is, and how Continue, Back, and Skip move through it.
public struct SetupFlow: Equatable, Sendable {
    public private(set) var step: SetupStep

    public static var count: Int { SetupStep.allCases.count }

    public init(from step: SetupStep = .welcome) {
        self.step = step
    }

    /// From one: "Step 3 of 8".
    public var position: Int { step.rawValue + 1 }
    public var isFirst: Bool { step == SetupStep.allCases.first }

    public mutating func next() {
        step = SetupStep(rawValue: step.rawValue + 1) ?? step
    }

    public mutating func back() {
        step = SetupStep(rawValue: step.rawValue - 1) ?? step
    }

    /// Everything setup asks is also in Settings and the menu, so skipping loses nothing.
    public mutating func skip() {
        step = .ready
    }
}

/// Whether setup opens when Earshot launches, and where.
public enum SetupLaunch {
    /// `markDone` records an earlier Earshot's user as done: they have used it, so the tour would
    /// only stand between them and the call they opened it for. `started` is setup opened before
    /// without being finished: quitting midway brings it back, whatever it downloaded.
    public static func atLaunch(done: Bool, started: Bool, hasModel: Bool, hasTranscripts: Bool)
        -> (show: SetupStep?, markDone: Bool)
    {
        let returning = !done && !started && (hasModel || hasTranscripts)
        if done || returning {
            return (hasModel ? nil : .models, returning)
        }
        return (.welcome, false)
    }
}

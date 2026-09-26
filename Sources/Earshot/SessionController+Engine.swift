import EarshotCapture
import EarshotKit
import Foundation

/// Keeping the engine loaded between sessions, or not, and what the menu says when it or the
/// capture behind a session fails.
extension SessionController {
    /// Loads the engine ahead of a session, when the menu opens or the app launches with "Keep
    /// engine loaded" on.
    func prewarm() {
        unload?.cancel()
        guard state == .idle, !engine.isRunning, let models = library.selection else { return }
        Task {
            do {
                _ = try await engine.ensureRunning(with: models)
                problems.resolve { if case .engineFailed = $0 { true } else { false } }
            } catch {
                log.error("engine warm-up failed: \(error.localizedDescription)")
                problems.report(Self.problem(startingEngine: error))
            }
        }
    }

    /// Unloads a warmed-up engine that no session used. The minute covers closing and reopening
    /// the menu while deciding; after it, ~1 GB of memory is worth more than a faster start.
    func scheduleUnload() {
        guard !preferences.keepEngineLoaded, state == .idle else { return }
        unload?.cancel()
        unload = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, state == .idle, !preferences.keepEngineLoaded else { return }
            engine.stop()
        }
    }

    /// The session cannot go on without its engine, and does not resume on a new one: word times
    /// restart with each stream and relabelling reads the whole recording, so it ends with what
    /// it has. An idle engine is launched again by the next start.
    /// A lost socket can reach the main actor before the exit does and have started the stop;
    /// the exit still replaces its connection-lost rows. Exits of an engine stopped on purpose
    /// never get here (`EngineServer` drops them).
    func engineExited() {
        switch state {
        case .idle, .starting:
            log.notice("the engine exited outside a session; the next start launches it again")
        case .recording, .stopping:
            problems.resolve { if case .connectionLost = $0 { true } else { false } }
            problems.report(.engineStopped)
            Task { await stop(byUser: false) }
        }
    }

    /// A start clears the last session's problems and its own failure.
    func beginStart() {
        problems.startSession()
        startFailure = nil
    }

    /// Recorded once: the menu lists it, and the window alerts with it. Set in the same turn as
    /// the failure, since a start without the microphone fails without ever awaiting and SwiftUI
    /// sees no change of state to react to.
    func reportStartFailure(_ problem: Problem) {
        problems.report(problem)
        startFailure = problem
    }

    /// What the menu shows: a missing model while there is none, then what was reported.
    var shownProblems: [Problem] {
        (library.selection == nil ? [.noModel] : []) + problems.all
    }

    /// Nil for a missing model, which `shownProblems` reports for as long as it lasts.
    static func problem(startingWith error: any Error) -> Problem? {
        switch error {
        case CaptureError.permissionDenied: .microphoneDenied
        case EngineError.missingModel: nil
        default: .captureFailed(actionable(error))
        }
    }

    static func problem(startingEngine error: any Error) -> Problem {
        switch error {
        case EngineError.missingBinary: .engineMissing
        case let failure as EngineLaunch.Failure: .engineFailed(failure.localizedDescription)
        default: .engineFailed("")
        }
    }

    /// A file system error names something the user can fix, such as a full disk; any other
    /// error means something only in the log.
    static func actionable(_ error: any Error) -> String {
        let domain = (error as NSError).domain
        return [NSCocoaErrorDomain, NSPOSIXErrorDomain].contains(domain)
            ? error.localizedDescription : ""
    }
}

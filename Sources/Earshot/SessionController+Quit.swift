import Foundation
import Observation

/// Ending the session when the app quits.
extension SessionController {
    /// Ends the session the way Stop does, or waits for the one already starting or stopping, and
    /// returns once it is saved. Nothing opens after it and no summary starts.
    func finishForQuit() async {
        quitting = true
        await wait { state == .starting }
        await stop()
        await wait { state == .stopping }
    }

    /// A start can be waiting on the microphone prompt, and a stop on relabelling; neither has an
    /// end to await, so this follows `state` until it moves on.
    private func wait(while condition: () -> Bool) async {
        while condition() {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = state
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}

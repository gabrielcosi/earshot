import Foundation

/// Keeping the engine loaded between sessions, or not.
extension SessionController {
    /// Loads the engine ahead of a session, when the menu opens or the app launches with "Keep
    /// engine loaded" on.
    func prewarm() {
        unload?.cancel()
        guard state == .idle, !engine.isRunning, let models = library.selection else { return }
        Task { _ = try? await engine.ensureRunning(with: models) }
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
}

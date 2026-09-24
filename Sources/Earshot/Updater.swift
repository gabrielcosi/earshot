import Foundation
import Observation
import Sparkle

/// Installs new releases from the appcast attached to the GitHub releases.
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private(set) var canCheck = false

    var checksAutomatically = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    /// `swift run` has no bundle and no feed, so it never looks for updates.
    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            // Sparkle changes canCheckForUpdates on the main thread.
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func check() {
        controller?.checkForUpdates(nil)
    }

    /// A menu bar app has no Dock icon to badge, so a scheduled update shows its window
    /// without taking focus from whatever is being transcribed.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}

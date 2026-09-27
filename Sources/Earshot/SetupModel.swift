import AVFoundation
import AppKit
import EarshotCapture
import EarshotKit
import Observation
import SwiftUI

/// The setup window's state: where it is, what its checks found, and whether setup is done.
/// Everything setup lets the user choose is the same setting Settings and the menu change; this
/// holds only what setup itself finds out.
@Observable
final class SetupModel {
    enum Ding: Equatable {
        case idle
        case listening
        case heard
        case notHeard
    }

    enum Microphone {
        case undetermined
        case allowed
        case denied

        static var current: Microphone {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .allowed
            case .notDetermined: .undetermined
            default: .denied
            }
        }
    }

    /// The download of the models setup offers, as its page shows it.
    enum Download: Equatable {
        case notStarted
        case downloading(Double)
        /// At 100 %, while the file's checksum is verified: a few seconds for the recognizer.
        case verifying
        case done
        case failed
        /// Not started: the volume has less free space than the models need.
        case noSpace(Int64)
    }

    var flow = SetupFlow()
    private(set) var ding = Ding.idle
    private(set) var microphone = Microphone.current
    /// Denied from setup's own button: Include my microphone was turned off, and the page says so.
    private(set) var microphoneTurnedOff = false
    private var spaceNeeded: Int64?
    /// The app is quitting: its windows closing with it does not finish setup.
    var quitting = false

    private static let doneKey = "setupDone"
    private static let startedKey = "setupStarted"

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
    /// Setup has opened on this Mac: quitting it midway brings it back, even once its models
    /// are downloaded.
    static var isStarted: Bool { UserDefaults.standard.bool(forKey: startedKey) }

    static func markDone() {
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    static func markStarted() {
        UserDefaults.standard.set(true, forKey: startedKey)
    }

    func refreshMicrophone() {
        microphone = .current
    }

    // MARK: Models

    /// The models setup downloads: the recognizer and speaker detection currently selected, the
    /// defaults on a new Mac.
    static func models(in library: ModelLibrary) -> [SpeechModel] {
        [library.transcription, library.diarization].compactMap { repo in
            library.catalog.models.first { $0.repo == repo }
        }
    }

    /// To the nearest 10 MB, as the page says "about": 849.1 MB reads as 850 MB.
    static func roundedSize(in library: ModelLibrary) -> Int64 {
        let size = Double(models(in: library).map(\.size).reduce(0, +))
        return Int64((size / 10_000_000).rounded()) * 10_000_000
    }

    func download(in library: ModelLibrary) -> Download {
        let models = Self.models(in: library)
        let missing = models.filter { !library.installed.contains($0.repo) }
        // A selected recognizer the catalog does not offer is missing too: the page never says
        // done while Earshot has nothing to listen with.
        if missing.isEmpty { return library.selection != nil ? .done : .notStarted }
        let running = missing.compactMap { library.progress[$0.repo] }
        if !running.isEmpty {
            if running.allSatisfy({ $0 >= 1 }), running.count == missing.count { return .verifying }
            let total = Double(models.map(\.size).reduce(0, +))
            let done = models.map { model in
                let fraction =
                    library.installed.contains(model.repo) ? 1 : library.progress[model.repo] ?? 0
                return Double(model.size) * fraction
            }
            return .downloading(total > 0 ? done.reduce(0, +) / total : 0)
        }
        if let spaceNeeded { return .noSpace(spaceNeeded) }
        if missing.contains(where: { library.failed.contains($0.repo) }) { return .failed }
        return .notStarted
    }

    /// Checks the free space first, so a full disk is said plainly instead of failing midway.
    func startDownload(in library: ModelLibrary) {
        let missing = Self.models(in: library).filter { !library.installed.contains($0.repo) }
        let needed = missing.map(\.size).reduce(0, +)
        if let available = library.availableCapacity, available < needed {
            spaceNeeded = needed
            return
        }
        spaceNeeded = nil
        missing.forEach(library.download)
    }

    func cancelDownload(in library: ModelLibrary) {
        Self.models(in: library).forEach(library.cancel)
    }

    // MARK: Permissions

    /// Only this button asks for the microphone. Granted, Include my microphone goes on; refused,
    /// it goes off, or every start after would fail on it.
    func allowMicrophone(_ preferences: Preferences) async {
        let granted = await MicrophoneCapture.requestAccess()
        microphone = granted ? .allowed : .denied
        // The user asked for the microphone here, so granting it turns it on.
        preferences.useMicrophone = granted
        guard !granted else { return }
        microphoneTurnedOff = true
        AccessibilityNotification.Announcement(
            "Earshot will write down only what your Mac plays."
        ).post()
    }

    /// The first time, macOS asks for System Audio Recording while the ding plays into a tap that
    /// may not hear it yet, and a grant reaches only a tap built after it. So when the prompt
    /// took Earshot's focus during the check, it runs once more when Earshot is active again.
    func playDing(_ controller: SessionController) async {
        guard ding != .listening else { return }
        ding = .listening
        controller.checkingSystemAudio = true
        defer { controller.checkingSystemAudio = false }
        let resigned = Task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didResignActiveNotification)
            {
                return true
            }
            return false
        }
        var heard = await Self.hearsDing()
        resigned.cancel()
        if !heard, await resigned.value, await Self.untilActive() {
            heard = await Self.hearsDing()
        }
        ding = heard ? .heard : .notHeard
        AccessibilityNotification.Announcement(
            heard ? "Earshot heard the ding." : "Earshot didn't hear the ding."
        ).post()
    }

    private static func hearsDing() async -> Bool {
        guard let pcm = try? await SystemAudioCheck.listen() else { return false }
        return !PCM.isSilent(pcm)
    }

    /// Time to read the permission prompt and answer it. Past it the check gives up as not
    /// heard, with Try Again, and no longer holds Start Listening back.
    private static let promptTimeout = Duration.seconds(60)

    /// False when Earshot is still inactive after `promptTimeout`.
    private static func untilActive() async -> Bool {
        guard !NSApp.isActive else { return true }
        let waiting = Task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification)
            {
                return true
            }
            return false
        }
        let timeout = Task {
            try? await Task.sleep(for: promptTimeout)
            waiting.cancel()
        }
        defer { timeout.cancel() }
        return await waiting.value
    }
}

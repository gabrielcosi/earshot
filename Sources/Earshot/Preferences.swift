import AppKit
import Foundation
import Observation
import ServiceManagement

/// App-wide settings that are not about one session.
@Observable
final class Preferences {
    /// The input device UID, or nil for the system default.
    var microphone: String? {
        didSet { UserDefaults.standard.set(microphone, forKey: "microphone") }
    }
    /// Off for a podcast or a video: only the Mac's audio is transcribed, and nothing the room
    /// hears is sent as "Me".
    var useMicrophone: Bool {
        didSet { UserDefaults.standard.set(useMicrophone, forKey: "useMicrophone") }
    }
    /// Removes what the speakers play from the microphone, for listening without headphones.
    /// Opt-in: with headphones there is no echo, and nothing should touch the microphone.
    var cancelSpeakerEcho: Bool {
        didSet { UserDefaults.standard.set(cancelSpeakerEcho, forKey: "cancelSpeakerEcho") }
    }
    /// The engine loads with the app and stays loaded: Start is instant, at the cost of about
    /// 1 GB of memory while idle. Off, it loads on demand and unloads after use.
    var keepEngineLoaded: Bool {
        didSet { UserDefaults.standard.set(keepEngineLoaded, forKey: "keepEngineLoaded") }
    }
    /// Reads the transcript with Apple's on-device model to suggest who each speaker is. Opt-in:
    /// it is a model reading the transcript, even if nothing leaves the Mac.
    var suggestSpeakerNames: Bool {
        didSet { UserDefaults.standard.set(suggestSpeakerNames, forKey: "suggestSpeakerNames") }
    }
    /// Saves each session's audio next to its transcript, both sides, as AAC (~23 MB an hour).
    var keepAudio: Bool {
        didSet { UserDefaults.standard.set(keepAudio, forKey: "keepAudio") }
    }
    /// Each API engine keeps its own address, model, and key, so switching engines back and forth
    /// does not lose either set. The three fields below are the selected engine's.
    var summaryEngine: Summarizer.Engine {
        didSet {
            UserDefaults.standard.set(summaryEngine.rawValue, forKey: "summaryEngine")
            let saved = Self.endpointSettings(for: summaryEngine)
            (summaryBaseURL, summaryModel, summaryAPIKey) = (saved.address, saved.model, saved.key)
        }
    }
    var summaryBaseURL: String {
        didSet {
            UserDefaults.standard.set(
                summaryBaseURL, forKey: "summaryBaseURL.\(summaryEngine.rawValue)")
        }
    }
    var summaryModel: String {
        didSet {
            UserDefaults.standard.set(
                summaryModel, forKey: "summaryModel.\(summaryEngine.rawValue)")
        }
    }
    var summaryAPIKey: String {
        didSet { Keychain.set(summaryAPIKey, for: "summaryAPIKey.\(summaryEngine.rawValue)") }
    }

    private struct EndpointSettings {
        let address: String
        let model: String
        let key: String
    }

    private static func endpointSettings(for engine: Summarizer.Engine) -> EndpointSettings {
        let defaults = UserDefaults.standard
        let name = engine.rawValue
        // Settings saved before engines had their own belong to the OpenAI-compatible one.
        let legacy = engine == .openAI
        return EndpointSettings(
            address: defaults.string(forKey: "summaryBaseURL.\(name)")
                ?? (legacy ? defaults.string(forKey: "summaryBaseURL") : nil) ?? "",
            model: defaults.string(forKey: "summaryModel.\(name)")
                ?? (legacy ? defaults.string(forKey: "summaryModel") : nil) ?? "",
            key: Keychain.get("summaryAPIKey.\(name)")
                ?? (legacy ? Keychain.get("summaryAPIKey") : nil)
                ?? ""
        )
    }
    var summarizeAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(summarizeAutomatically, forKey: "summarizeAutomatically")
        }
    }

    var summaryEndpoint: Summarizer.Endpoint? {
        guard let url = URL(string: summaryBaseURL), url.scheme != nil, !summaryModel.isEmpty
        else { return nil }
        return Summarizer.Endpoint(baseURL: url, model: summaryModel, apiKey: summaryAPIKey)
    }

    var keepAwake: Bool {
        didSet { UserDefaults.standard.set(keepAwake, forKey: "keepAwake") }
    }
    var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            applyDockIcon()
        }
    }
    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
            loginChanges += 1
        }
    }
    /// SMAppService is not observable; this makes a toggle re-read `openAtLogin`.
    private var loginChanges = 0

    /// Where transcripts are saved. The sandbox allows the app's own container, or a folder the
    /// user picked, remembered as a security-scoped bookmark.
    private(set) var transcriptsFolder: URL
    private static let defaultTranscriptsFolder = URL.documentsDirectory.appending(path: "Earshot")

    init() {
        let defaults = UserDefaults.standard
        microphone = defaults.string(forKey: "microphone")
        keepAwake = defaults.object(forKey: "keepAwake") as? Bool ?? true
        useMicrophone = defaults.object(forKey: "useMicrophone") as? Bool ?? true
        cancelSpeakerEcho = defaults.bool(forKey: "cancelSpeakerEcho")
        keepEngineLoaded = defaults.bool(forKey: "keepEngineLoaded")
        keepAudio = defaults.bool(forKey: "keepAudio")
        let engine =
            defaults.string(forKey: "summaryEngine").flatMap(Summarizer.Engine.init) ?? .apple
        summaryEngine = engine
        let saved = Self.endpointSettings(for: engine)
        (summaryBaseURL, summaryModel, summaryAPIKey) = (saved.address, saved.model, saved.key)
        summarizeAutomatically = defaults.bool(forKey: "summarizeAutomatically")
        suggestSpeakerNames = defaults.bool(forKey: "suggestSpeakerNames")
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? false
        transcriptsFolder = Self.resolveBookmark() ?? Self.defaultTranscriptsFolder
    }

    var usesDefaultTranscriptsFolder: Bool {
        transcriptsFolder == Self.defaultTranscriptsFolder
    }

    /// Takes a folder from an open panel, which is what grants the sandbox access to it.
    func setTranscriptsFolder(_ folder: URL) throws {
        let bookmark = try folder.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: "transcriptsBookmark")
        transcriptsFolder.stopAccessingSecurityScopedResource()
        _ = folder.startAccessingSecurityScopedResource()
        transcriptsFolder = folder
    }

    func resetTranscriptsFolder() {
        UserDefaults.standard.removeObject(forKey: "transcriptsBookmark")
        transcriptsFolder.stopAccessingSecurityScopedResource()
        transcriptsFolder = Self.defaultTranscriptsFolder
    }

    /// Access is held for the life of the app, so saving never has to reopen it.
    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "transcriptsBookmark") else {
            return nil
        }
        var stale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                bookmarkDataIsStale: &stale),
            url.startAccessingSecurityScopedResource()
        else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(fresh, forKey: "transcriptsBookmark")
        }
        return url
    }

    /// While the main window or Settings is open the app is in the Dock and ⌘Tab like any app
    /// with a window, whatever `showDockIcon` says.
    var openWindows = 0 {
        didSet { applyDockIcon() }
    }

    func applyDockIcon() {
        let policy: NSApplication.ActivationPolicy =
            showDockIcon || openWindows > 0 ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // An app that turns regular while active shows in ⌘Tab only once activated again.
        if policy == .regular, openWindows > 0 { NSApp.activate() }
    }
}

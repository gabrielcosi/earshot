import EarshotCapture
import EarshotKit
import Foundation
import Observation
@preconcurrency import Translation
import os

@Observable
final class SessionController {
    enum State: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case stopping
    }

    private(set) var state = State.idle
    var transcript = Transcript()
    /// Every transcript; the Markdown files are copies written from it.
    @ObservationIgnored let store: TranscriptStore
    /// The current session's transcript in the store; nil until its first line is stored.
    private(set) var savedID: UUID?
    /// The current session's id in the store, from its start.
    @ObservationIgnored private var sessionID = UUID()
    /// The current session has ended in the store; what changes after it is exported.
    @ObservationIgnored var sealed = false
    /// What the store holds of the session, so each final writes only what changed.
    @ObservationIgnored private var persisted: [Utterance] = []
    /// The session that just ended, kept until its speakers are named so their lines can be
    /// played; deleted then, at the next start, or when the app quits.
    var lastRecording: Recording?
    var namingRequest: NamingRequest?
    /// A session ended on its own and the menu has not been opened since.
    var needsAttention = false
    /// The app is quitting: the session ends and saves, with nothing after it.
    @ObservationIgnored var quitting = false
    /// Transcripts being summarized right now, and those whose last summary failed.
    var summarizing: Set<UUID> = []
    var failedSummaries: [UUID: Problem] = [:]
    /// Whether each transcript's Markdown file is up to date, as last checked.
    var exports: [UUID: TranscriptExporter.Status] = [:]
    /// Transcripts being exported, and those changed again since their export started.
    @ObservationIgnored var exportRuns: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var exportAgain: Set<UUID> = []
    var names: [Speaker: String] = [:]
    /// What keeps Earshot from working right now, shown in the menu.
    var problems = Problems()
    /// Applied wherever text is shown or written; a change reaches each file at its next export.
    var rules: WordRules {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: "wordRules") }
    }
    /// The languages spoken in what the user transcribes; empty means any.
    var spokenLanguages: [String] {
        didSet { UserDefaults.standard.set(spokenLanguages, forKey: "spokenLanguages") }
    }
    /// The user's own language: everything else gets translated into it.
    var primaryLanguage: String {
        didSet {
            UserDefaults.standard.set(primaryLanguage, forKey: "primaryLanguage")
            translator.reset()
            attempted = [:]
            problems.resolve(where: \.isTranslation)
            translatePending()
        }
    }
    var translationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(translationEnabled, forKey: "translationEnabled")
            problems.resolve(where: \.isTranslation)
            attempted = [:]
            translatePending()
        }
    }
    /// Set when the user asks for a language pair's download; the main window presents Apple's
    /// prompt for it.
    var downloadRequest: TranslationSession.Configuration?
    private(set) var translationLanguages: [Locale.Language] = []

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    @ObservationIgnored let engine = EngineServer()
    let library = ModelLibrary()
    let preferences = Preferences()
    @ObservationIgnored private var microphone: MicrophoneCapture?
    @ObservationIgnored private var system: SystemAudioCapture?
    /// Every app, as the echo canceller's copy of the speakers, while the setting is on: the
    /// transcribed capture may hold only chosen apps, and the rest would stay in the microphone.
    @ObservationIgnored private var echoReference: SystemAudioCapture?
    /// The apps to transcribe, empty for every app; not kept, so no launch waits for a gone app.
    var sources: [AudioSource] = [] {
        didSet { system?.listen(to: Set(sources.map(\.id))) }
    }
    @ObservationIgnored private var clients: [Channel: RealtimeClient] = [:]
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    private(set) var startedAt = Date.now
    @ObservationIgnored let translator = Translator()
    /// Source text last sent for translation per utterance, so each version is tried once.
    @ObservationIgnored var attempted: [UUID: String] = [:]
    @ObservationIgnored private var awake: (any NSObjectProtocol)?
    @ObservationIgnored private var connecting: Task<Void, Never>?
    @ObservationIgnored var unload: Task<Void, Never>?
    /// The session is capturing but the engine is still loading; the transcript catches up.
    private(set) var engineLoading = false
    /// Stream time each channel's audio has been refined up to.
    @ObservationIgnored private var refinedUntil: [Channel: Double] = [:]
    @ObservationIgnored var refinements: [Task<Void, Never>] = []
    @ObservationIgnored private var recording: Recording?
    @ObservationIgnored private var microphoneRecording: Recording?
    /// The clip runs a little past the last word, so its final phoneme is not cut.
    private static let refinementTail = 0.3
    @ObservationIgnored var liveInFlight: Set<Channel> = []
    @ObservationIgnored var liveStale: Set<Channel> = []
    let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "session")

    /// The engine answers a commit in about 100 ms; this only bounds a dead socket.
    private static let commitTimeout = Duration.seconds(5)

    init() {
        let (store, storeProblem) = Self.openStore()
        self.store = store
        let defaults = UserDefaults.standard
        spokenLanguages = defaults.stringArray(forKey: "spokenLanguages") ?? []
        rules =
            defaults.data(forKey: "wordRules").flatMap {
                try? JSONDecoder().decode(WordRules.self, from: $0)
            } ?? WordRules()
        primaryLanguage =
            defaults.string(forKey: "primaryLanguage") ?? Locale.current.language.minimalIdentifier
        translationEnabled = defaults.object(forKey: "translationEnabled") as? Bool ?? true
        Task { translationLanguages = await translator.supportedLanguages() }
        engine.onExit = { [weak self] in self?.engineExited() }
        if let storeProblem { problems.report(storeProblem) }
    }

    /// Starts capturing at once. The engine may still be loading: audio waits in the sinks and
    /// goes through when it is ready, so the button responds immediately and nothing said during
    /// the load is lost; the transcript catches up.
    func start() async {
        guard state == .idle else { return }
        state = .starting
        problems.startSession()
        unload?.cancel()
        discardLastRecording()
        do {
            let useMicrophone = preferences.useMicrophone
            if useMicrophone {
                guard await MicrophoneCapture.requestAccess() else {
                    throw CaptureError.permissionDenied("Microphone")
                }
            }
            guard let models = library.selection else { throw EngineError.missingModel }
            transcript = Transcript()
            attempted = [:]
            refinedUntil = [:]
            refinements = []
            names = [:]
            savedID = nil
            sessionID = UUID()
            sealed = false
            persisted = []
            startedAt = .now

            let (systemSink, microphoneSink) = try startCapture(microphone: useMicrophone)
            if preferences.keepAwake {
                awake = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .userInitiated],
                    reason: "Transcribing audio")
            }
            state = .recording(since: startedAt)
            engineLoading = !engine.isRunning
            connecting = Task {
                await connect(models: models, system: systemSink, microphone: microphoneSink)
            }
        } catch {
            log.error("start failed: \(error.localizedDescription)")
            if let problem = Self.problem(startingWith: error) { problems.report(problem) }
            teardown()
            state = .idle
        }
    }

    private func startCapture(microphone useMicrophone: Bool) throws -> (AudioSink, AudioSink?) {
        let systemSink = AudioSink()
        let microphoneSink = useMicrophone ? AudioSink() : nil
        // A new canceller per session: it starts with no echo path. Nothing exists when the
        // setting is off, so headphone users' audio is never touched.
        let canceller = useMicrophone && preferences.cancelSpeakerEcho ? EchoCanceller() : nil
        if let microphoneSink {
            let microphoneRecording = try Recording(.microphone)
            self.microphoneRecording = microphoneRecording
            let microphone = MicrophoneCapture()
            try microphone.start(deviceUID: preferences.microphone) { pcm in
                let heard = canceller?.process(pcm) ?? pcm
                guard !heard.isEmpty else { return }
                microphoneSink.send(heard)
                microphoneRecording.append(heard)
            }
            self.microphone = microphone
        }
        let recording = try Recording(.system)
        self.recording = recording
        let system = SystemAudioCapture(sources: Set(sources.map(\.id)))
        try system.start { pcm in
            systemSink.send(pcm)
            recording.append(pcm)
        }
        self.system = system
        if let canceller {
            let reference = SystemAudioCapture()
            try reference.start(
                onAudio: { canceller.feedFarEnd($0) }, onRestart: { canceller.reset() })
            echoReference = reference
        }
        return (systemSink, microphoneSink)
    }

    private func connect(models: EngineServer.Models, system: AudioSink, microphone: AudioSink?)
        async
    {
        do {
            let endpoint = try await engine.ensureRunning(with: models)
            guard isRecording else { return }
            system.attach(connect(.system, diarize: true, to: endpoint))
            microphone?.attach(connect(.microphone, diarize: false, to: endpoint))
        } catch {
            log.error("engine start failed: \(error.localizedDescription)")
            problems.report(Self.problem(startingEngine: error))
            teardown()
            state = .idle
        }
        engineLoading = false
    }

    /// `byUser` is false for a session that ends on its own; it then opens nothing and takes no
    /// focus, and the menu bar ear shows a mark instead.
    func stop(byUser: Bool = true) async {
        guard isRecording else { return }
        state = .stopping
        if !byUser { needsAttention = true }
        microphone?.stop()
        system?.stop()
        echoReference?.stop()
        await connecting?.value
        connecting = nil
        clients.values.forEach { $0.commit() }
        let clients = clients
        let deadline = Task {
            try? await Task.sleep(for: Self.commitTimeout)
            clients.values.forEach { $0.close() }
        }
        for listener in listeners { await listener.value }
        deadline.cancel()
        let (recording, microphoneRecording) = (recording, microphoneRecording)
        (self.recording, self.microphoneRecording) = (nil, nil)
        teardown()
        if let recording { await relabelSpeakers(from: recording) }
        persist()
        await seal()
        if let recording {
            microphoneRecording?.finish()
            if preferences.keepAudio, let savedID {
                await keepAudio(system: recording, microphone: microphoneRecording, for: savedID)
                recording.discard()
            } else {
                lastRecording = recording
            }
            microphoneRecording?.discard()
        }
        state = .idle
        if !preferences.keepEngineLoaded { engine.stop() }
        sessionEnded(byUser: byUser)
    }

    /// Names a transcript's speakers in the store, and in the session still open in the app.
    func name(speakers names: [Speaker: String], in transcript: UUID) {
        do {
            try store.rename(transcript, names)
        } catch {
            reportSavingFailed(error)
            return
        }
        if transcript == savedID {
            for (speaker, name) in names {
                let name = name.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { self.names[speaker] = name }
            }
        }
        scheduleExport(transcript)
    }

    private func connect(_ channel: Channel, diarize: Bool, to endpoint: EngineEndpoint)
        -> RealtimeClient
    {
        let client = RealtimeClient(
            engine: endpoint,
            settings: SessionSettings(
                speakerDiarization: diarize,
                language: LanguagePolicy.liveLanguage(allowed: spokenLanguages),
                speechContexts: rules.speechContexts)
        )
        clients[channel] = client
        listeners.append(
            Task { [weak self] in
                for await event in client.events { self?.handle(event, on: channel) }
            })
        return client
    }

    private func handle(_ event: ServerEvent, on channel: Channel) {
        switch event {
        case .partial(let delta):
            transcript.applyPartial(delta, on: channel)
            translateLive(channel)
        case .final(let text, let words):
            let final = transcript.applyFinal(transcript: text, words: words, on: channel)
            persist()
            translatePending()
            refine(final, on: channel)
        case .error(let message):
            log.error("\(channel.rawValue, privacy: .public) stream: \(message, privacy: .public)")
            if isRecording { problems.report(.engineError(channel)) }
        case .disconnected(let message):
            log.error("\(channel.rawValue, privacy: .public) lost: \(message, privacy: .public)")
            guard isRecording else { return }
            problems.report(engine.isRunning ? .connectionLost(channel) : .engineStopped)
            // stop() waits for this listener to finish, so it cannot run inside it.
            Task { await stop(byUser: false) }
        case .committed:
            clients[channel]?.close()
        case .sessionCreated, .other:
            break
        }
    }

    /// Transcribes a final's audio again on its own, from the end of the channel's previous final,
    /// and swaps in the result. A fresh decode recognizes a language switch from the first word,
    /// which the live stream loses while its decoder is still on the previous language.
    private func refine(_ final: AppliedFinal, on channel: Channel) {
        guard let end = final.end.map({ $0 + Self.refinementTail }), let client = clients[channel]
        else { return }
        let start = refinedUntil[channel] ?? 0
        refinedUntil[channel] = end
        guard let pcm = client.audio(from: start, to: end), let endpoint = engine.endpoint else {
            return
        }
        let (allowed, contexts) = (spokenLanguages, rules.speechContexts)
        refinements.append(
            Task {
                do {
                    let words = try await Retranscriber.transcribe(
                        pcm: pcm, engine: endpoint, allowed: allowed, contexts: contexts)
                    let shifted = words.map {
                        Word(word: $0.word, start: $0.start + start, end: $0.end + start)
                    }
                    transcript.refine(final, with: shifted)
                    persist()
                    translatePending()
                } catch {
                    log.error("refinement failed: \(error, privacy: .public)")
                }
            })
    }

    private func teardown() {
        recording?.discard()
        recording = nil
        microphoneRecording?.discard()
        microphoneRecording = nil
        if let awake { ProcessInfo.processInfo.endActivity(awake) }
        awake = nil
        microphone?.stop()
        system?.stop()
        echoReference?.stop()
        microphone = nil
        system = nil
        echoReference = nil
        clients.values.forEach { $0.close() }
        clients = [:]
        listeners.forEach { $0.cancel() }
        listeners = []
    }

    /// Writes the session's paragraphs to the store; called after every final, so a crash loses
    /// nothing. The Markdown file is written when the session ends.
    func persist() {
        guard !transcript.utterances.isEmpty else { return }
        do {
            try store.saveLive(
                sessionID, startedAt: startedAt, utterances: transcript.utterances,
                previous: persisted)
            persisted = transcript.utterances
            if savedID != sessionID { savedID = sessionID }
        } catch {
            reportSavingFailed(error)
        }
    }
}

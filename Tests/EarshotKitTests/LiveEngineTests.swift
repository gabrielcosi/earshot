import Foundation
import Testing

@testable import EarshotKit

/// Streams fixture clips through a running engine (`mise run serve`) the way the app does: at
/// real-time pace, in the process tap's buffer size, next to a second (microphone) session.
/// Endpointing is measured against wall-clock audio, so faster pacing hides the finals; the
/// engine coordinates input across sessions, so a lone session hides ingress stalls. Serialized:
/// the app runs two sessions, and parallel tests would stack more on the engine than it ever sees.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["EARSHOT_LIVE"] == "1"))
struct LiveEngineTests {
    /// `EARSHOT_API_KEY` tests against an engine that requires a key, as the app launches it.
    private static let engine = EngineEndpoint(
        url: URL(string: "http://127.0.0.1:8765/") ?? URL(filePath: "/"),
        apiKey: ProcessInfo.processInfo.environment["EARSHOT_API_KEY"])
    private static let bytesPerSecond = 32_000.0
    /// What the process tap produces per IO cycle after resampling to 16 kHz (171 samples).
    private static let tapBufferBytes = 342
    /// What AVAudioEngine's input tap produces after resampling (4800 frames at 48 kHz).
    private static let microphoneBufferBytes = 3200
    /// Endpointing waits 0.8 s of silence; the rest is decoding and the socket. A stalled
    /// session delivers its first final 5 s+ late.
    private static let finalLatencyLimit = 1.5

    @Test func endpointingSplitsTurnsAndDiarizationSeparatesVoices() async throws {
        let (finals, _) = try await stream(fixture: "two-speakers", diarize: true)
        #expect(finals.count >= 2)
        let speakers = Set(finals.flatMap(\.words).compactMap(\.speaker))
        #expect(speakers.count == 2)
    }

    @Test func autoDetectionFollowsLanguageSwitches() async throws {
        let text = try await stream(fixture: "three-languages", diarize: true).finals
            .map(\.transcript).joined(separator: " ")
        for word in ["Revenue", "Lieferung", "necesitamos"] {
            #expect(text.localizedCaseInsensitiveContains(word), "missing \(word) in \(text)")
        }
    }

    /// Each final's audio, from the end of the previous final, transcribed on its own. The fixture
    /// switches language after 0.6 s pauses; live, the Spanish turn starts as "Ich doile" because
    /// the decoder is still on German, and the second pass hears "Estoy de acuerdo".
    @Test func refinementKeepsTheOpeningWordsOfEachLanguage() async throws {
        let (finals, client) = try await stream(fixture: "quick-switch", diarize: true)
        var previousEnd = 0.0
        var refined: [String] = []
        for final in finals {
            let end = (final.words.last?.end ?? previousEnd) + Self.refinementTail
            let pcm = try #require(client.audio(from: previousEnd, to: end))
            let words = try await Retranscriber.transcribe(
                pcm: pcm, engine: Self.engine, allowed: [])
            refined.append(words.map(\.word).joined(separator: " "))
            previousEnd = end
        }
        let live = finals.map(\.transcript).joined(separator: " | ")
        let text = refined.joined(separator: " | ")
        print("live:    \(live)\nrefined: \(text)")
        for phrase in ["Thanks", "Ich glaube", "Estoy de acuerdo"] {
            #expect(text.localizedCaseInsensitiveContains(phrase), "missing \(phrase) in \(text)")
        }
    }

    /// Auto-detection writes this Romanian turn in Cyrillic. Restricted to English and Romanian,
    /// the second pass falls back to both and keeps the one that reads as Romanian.
    @Test func refinementStaysWithinTheConfiguredLanguages() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/romanian", withExtension: "wav"))
        let pcm = try Data(contentsOf: url).dropFirst(44)
        let free = try await Retranscriber.transcribe(pcm: pcm, engine: Self.engine, allowed: [])
        let kept = try await Retranscriber.transcribe(
            pcm: pcm, engine: Self.engine, allowed: ["en-US", "ro-RO"])
        let text = kept.map(\.word).joined(separator: " ")
        print("auto:       \(free.map(\.word).joined(separator: " "))\nrestricted: \(text)")
        #expect(LanguagePolicy.scripts(in: text).isSubset(of: ["Latn"]))
        #expect(text.localizedCaseInsensitiveContains("trimestrul"))
    }

    /// The app's whole pipeline on three voices with 0.6 s gaps: live finals, refined per line,
    /// then relabelled from diarizing the full recording.
    @Test func relabellingGivesEachVoiceItsOwnParagraph() async throws {
        let transcript = try await relabelled(fixture: "quick-switch")
        #expect(transcript.utterances.count == 3)
        #expect(Set(transcript.utterances.map(\.speaker)).count == 3)
        #expect(transcript.utterances.last?.text.hasPrefix("Estoy") == true)
    }

    /// Two voices taking turns with 0.15 s gaps. The engine's word times are emission times,
    /// 0.3-0.5 s after the speech, so placing words into turns by time gives each turn's last
    /// word to the next speaker; each paragraph must begin and end with its own voice's words.
    @Test func quickTurnsKeepTheirLastWord() async throws {
        let transcript = try await relabelled(fixture: "quick-turns")
        let paragraphs = transcript.utterances.map(\.text)
        print("relabelled:\n  \(paragraphs.joined(separator: "\n  "))")
        #expect(paragraphs.count == 4)
        for (paragraph, (first, last)) in zip(
            paragraphs,
            [("Good", "numbers"), ("Thanks", "product"), ("So", "week"), ("Every", "it")])
        {
            let words = paragraph.split(separator: " ").map {
                $0.trimmingCharacters(in: .punctuationCharacters)
            }
            #expect(words.first == first && words.last == last, "\(paragraph)")
        }
    }

    /// Live finals refined per line, then each turn from the whole recording's diarization
    /// transcribed from its own audio: what the app does from Start to Stop.
    private func relabelled(fixture: String) async throws -> Transcript {
        let (finals, client) = try await stream(fixture: fixture, diarize: true)
        var transcript = Transcript()
        var previousEnd = 0.0
        for final in finals {
            let applied = transcript.applyFinal(
                transcript: final.transcript, words: final.words, on: .system)
            let end = (final.words.last?.end ?? previousEnd) + Self.refinementTail
            let pcm = try #require(client.audio(from: previousEnd, to: end))
            let words = try await Retranscriber.transcribe(
                pcm: pcm, engine: Self.engine, allowed: [])
            transcript.refine(
                applied,
                with: words.map {
                    Word(word: $0.word, start: $0.start + previousEnd, end: $0.end + previousEnd)
                })
            previousEnd = end
        }
        let before = transcript.utterances.map { "\($0.speaker.label): \($0.text)" }
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(fixture)", withExtension: "wav"))
        let pcm = try Data(contentsOf: url).dropFirst(44)
        let turns = try await Diarizer.diarize(pcm: pcm, engine: Self.engine)
        transcript.relabel(
            try await Retranscriber.transcribe(
                turns: turns, pcm: pcm, engine: Self.engine, allowed: []))
        let after = transcript.utterances.map { "\($0.speaker.label): \($0.text)" }
        print(
            "live:\n  \(before.joined(separator: "\n  "))\nrelabelled:\n  \(after.joined(separator: "\n  "))"
        )
        return transcript
    }

    /// A session starts before the engine has loaded: the first seconds wait in a sink and go
    /// through when the session attaches. None of the opening words may be lost.
    @Test func audioCapturedBeforeTheEngineIsReadyIsTranscribed() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/two-speakers", withExtension: "wav"))
        let pcm = try Data(contentsOf: url).dropFirst(44)
        let sink = AudioSink()
        let started = ContinuousClock.now
        let clock = ContinuousClock()
        let capture = Task {
            var offset = pcm.startIndex
            while offset < pcm.endIndex {
                let end = min(offset + Self.tapBufferBytes, pcm.endIndex)
                sink.send(Data(pcm[offset..<end]))
                offset = end
                try await clock.sleep(
                    until: started + .seconds(Double(offset - pcm.startIndex) / Self.bytesPerSecond)
                )
            }
        }
        try await clock.sleep(until: started + Self.engineLoad)
        let client = RealtimeClient(
            engine: Self.engine, settings: SessionSettings(speakerDiarization: false))
        sink.attach(client)
        try await capture.value
        client.commit()
        var text: [String] = []
        for await event in client.events {
            if case .final(let transcript, _) = event { text.append(transcript) }
            if case .committed = event { client.close() }
        }
        let joined = text.joined(separator: " ")
        #expect(joined.hasPrefix("Good morning everyone"), "got \(joined)")
        #expect(joined.contains("storage product"))
    }

    /// Stands in for the engine loading while the session has already started.
    private static let engineLoad = Duration.seconds(3)

    /// The vocabulary reaches the engine on both paths: the live session and the second pass.
    @Test func vocabularyFixesNamesLiveAndInTheSecondPass() async throws {
        var rules = WordRules()
        rules.vocabulary = ["Jane Doe", "Zentari", "Quorvex", "Velmora"]
        let client = RealtimeClient(
            engine: Self.engine,
            settings: SessionSettings(
                speakerDiarization: false, language: "en-US",
                speechContexts: rules.speechContexts))
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/names", withExtension: "wav"))
        let pcm = try Data(contentsOf: url).dropFirst(44)
        let sender = feed(pcm, to: client, in: Self.microphoneBufferBytes, from: .now)
        var live: [String] = []
        for await event in client.events {
            if case .final(let transcript, _) = event { live.append(transcript) }
            if case .committed = event { client.close() }
        }
        try await sender.value
        let refined = try await Retranscriber.transcribe(
            pcm: pcm, engine: Self.engine, allowed: ["en-US"], contexts: rules.speechContexts
        ).map(\.word).joined(separator: " ")
        for text in [live.joined(separator: " "), refined] {
            for name in ["Zentari", "Quorvex"] {
                #expect(text.contains(name), "missing \(name) in \(text)")
            }
        }
    }

    /// The refinement clip runs a little past the last word, so its final phoneme is not cut.
    private static let refinementTail = 0.3

    private struct Final {
        let transcript: String
        let words: [Word]
    }

    /// Streams `fixture` as system audio, with the same clip on a microphone session alongside,
    /// and checks that every system final arrives within `finalLatencyLimit` of its last word.
    private func stream(fixture: String, diarize: Bool) async throws -> (
        finals: [Final], system: RealtimeClient
    ) {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(fixture)", withExtension: "wav"))
        let pcm = try Data(contentsOf: url).dropFirst(44)
        let system = RealtimeClient(
            engine: Self.engine,
            settings: SessionSettings(speakerDiarization: diarize, language: Languages.auto))
        let microphone = RealtimeClient(
            engine: Self.engine,
            settings: SessionSettings(speakerDiarization: false, language: Languages.auto))
        let started = ContinuousClock.now
        let senders = [
            feed(pcm, to: system, in: Self.tapBufferBytes, from: started),
            feed(pcm, to: microphone, in: Self.microphoneBufferBytes, from: started),
        ]
        let drained = Task { await drain(microphone) }

        var finals: [Final] = []
        for await event in system.events {
            switch event {
            case .final(let transcript, let words) where !transcript.isEmpty:
                let elapsed = ContinuousClock.now - started
                let latency = elapsed - .seconds(words.last?.end ?? 0)
                #expect(
                    latency < .seconds(Self.finalLatencyLimit),
                    "final \"\(transcript)\" arrived \(latency) after its last word")
                finals.append(Final(transcript: transcript, words: words))
            case .committed:
                system.close()
            case .error(let message), .disconnected(let message):
                Issue.record("engine error: \(message)")
                system.close()
            default:
                break
            }
        }
        for sender in senders { try await sender.value }
        await drained.value
        return (finals, system)
    }

    private func feed(
        _ pcm: Data, to client: RealtimeClient, in bufferBytes: Int,
        from started: ContinuousClock.Instant
    ) -> Task<Void, any Error> {
        Task {
            let clock = ContinuousClock()
            var offset = pcm.startIndex
            while offset < pcm.endIndex {
                let end = min(offset + bufferBytes, pcm.endIndex)
                client.send(audio: Data(pcm[offset..<end]))
                offset = end
                let sent = Double(offset - pcm.startIndex) / Self.bytesPerSecond
                try await clock.sleep(until: started + .seconds(sent))
            }
            client.commit()
        }
    }

    private func drain(_ client: RealtimeClient) async {
        for await event in client.events {
            switch event {
            case .committed: client.close()
            case .error(let message), .disconnected(let message):
                Issue.record("microphone session error: \(message)")
                client.close()
            default: break
            }
        }
    }

    /// Offline diarization holds about 6.6 minutes; a longer recording still gets speaker turns.
    @Test func aRecordingLongerThanOfflineDiarizationStillGetsTurns() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/two-speakers", withExtension: "wav"))
        let clip = try Data(contentsOf: url).dropFirst(44)
        let silence = Data(count: 32_000 * 20)
        var pcm = Data()
        while Double(pcm.count) / 32_000 < Diarizer.offlineLimit + 60 { pcm += clip + silence }
        let turns = try await Diarizer.diarize(pcm: pcm, engine: Self.engine)
        #expect(Set(turns.map(\.speaker)).count >= 2)
        #expect((turns.last?.end ?? 0) > Diarizer.offlineLimit)
    }

}

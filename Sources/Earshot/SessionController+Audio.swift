import EarshotCapture
import EarshotKit
import Foundation

/// What happens to a session's audio after it stops: speakers relabelled from the whole
/// recording, the audio kept or held for naming, and clips for hearing a speaker.
extension SessionController {
    /// Diarizes the whole system recording once the session ends and transcribes each speaker
    /// turn from its own audio, so every remote paragraph is one speaker's. Refinements still
    /// running are awaited first, so none lands on the rebuilt transcript.
    func relabelSpeakers(from recording: Recording) async {
        // The session's figures, once its paragraphs are the last ones.
        defer { translationLog.summarize() }
        recording.finish()
        let start = ContinuousClock.now
        for refinement in refinements { await refinement.value }
        refinements = []
        log.notice(
            "waited \(Self.seconds(since: start), format: .fixed(precision: 1)) s for refinements"
        )
        guard library.selection?.diarization != nil, let endpoint = engine.endpoint,
            let pcm = try? Data(contentsOf: recording.url, options: .alwaysMapped), !pcm.isEmpty
        else { return }
        do {
            let diarizing = ContinuousClock.now
            let turns = try await Diarizer.diarize(pcm: pcm, engine: endpoint)
            let diarized = Self.seconds(since: diarizing)
            let transcribing = ContinuousClock.now
            let transcribed = try await Retranscriber.transcribe(
                turns: turns, pcm: pcm, engine: endpoint, allowed: spokenLanguages,
                contexts: rules.speechContexts)
            // The engine answered every turn, so none holding words means none had speech.
            guard transcript.relabel(transcribed) || turns.isEmpty else {
                log.notice("no speech in \(turns.count) turns; the live speakers stay")
                return
            }
            log.notice(
                "relabelled \(pcm.count / 32_000) s of audio: \(turns.count) turns, \(Set(turns.map(\.speaker)).count) speakers, diarized in \(diarized, format: .fixed(precision: 1)) s, transcribed in \(Self.seconds(since: transcribing), format: .fixed(precision: 1)) s"
            )
            if translationEnabled {
                let coverage = transcript.sentenceCoverage
                translationLog.relabelled(hits: coverage.known, misses: coverage.pending)
            }
            // Stored before the session is sealed, so its first Markdown file has them.
            persist()
            translationChanged()
        } catch {
            log.error("speaker relabelling failed: \(error, privacy: .public)")
            problems.report(.speakersNotRelabelled)
        }
    }

    /// For the stop path's timings in the log.
    nonisolated private static func seconds(since start: ContinuousClock.Instant) -> Double {
        (ContinuousClock.now - start) / .seconds(1)
    }

    /// Where a capture sends the audio kept of it, when it is kept.
    static func output(_ recording: Recording?) -> KeptOutput? {
        recording.map { recording in KeptOutput(rate: recording.rate, onAudio: recording.append) }
    }

    func clip(at start: Double, seconds: Double) -> Data? {
        lastRecording?.clip(from: start, seconds: seconds)
    }

    /// Once relabelling is done and the session sealed: the kept audio goes to the transcript,
    /// and the system recording stays for naming unless the kept audio holds it.
    func finish(_ recordings: SessionRecordings, keeping: KeptAudioEncoding?) async {
        recordings.finish()
        if let keeping { await keepAudio(keeping) }
        if keeping != nil, savedID != nil {
            recordings.system.discard()
        } else {
            lastRecording = recordings.system
        }
        recordings.discardAllButSystem()
    }

    /// Kept audio being encoded, among the recordings until the session's transcript holds it.
    struct KeptAudioEncoding {
        let file: URL
        /// The failed write when only part was kept, and how long the encoding took.
        let task: Task<(failure: NSError?, seconds: Double), any Error>
    }

    /// Encoding an hour takes about 20 s, so it runs off the main actor while the speakers are
    /// relabelled. The file waits with the recordings, which a launch clears, since whether the
    /// session has a transcript is known only after relabelling.
    func startKeepingAudio(_ recordings: SessionRecordings) -> KeptAudioEncoding {
        let file = Recording.directory.appending(path: "\(UUID().uuidString).m4a")
        return KeptAudioEncoding(
            file: file,
            task: Task.detached(priority: .utility) {
                let start = ContinuousClock.now
                let failure = try recordings.keep(to: file)
                return (failure, Self.seconds(since: start))
            })
    }

    /// Moves the encoded audio into the store's folder, never into the transcripts folder, or
    /// deletes it when the session has no transcript, which may have been deleted meanwhile.
    func keepAudio(_ encoding: KeptAudioEncoding) async {
        let waiting = ContinuousClock.now
        let result = await encoding.task.result
        if case .success(let encoded) = result {
            log.notice(
                "encoded the kept audio in \(encoded.seconds, format: .fixed(precision: 1)) s; waited \(Self.seconds(since: waiting), format: .fixed(precision: 1)) s for it"
            )
        }
        guard let transcript = savedID else {
            try? FileManager.default.removeItem(at: encoding.file)
            return
        }
        let name = "\(transcript.uuidString).m4a"
        let destination = Self.audioFolder.appending(path: name)
        do {
            let failure = try result.get().failure
            try FileManager.default.createDirectory(
                at: Self.audioFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: encoding.file, to: destination)
            do {
                try store.setAudio(name, for: transcript)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            if let failure {
                log.error("kept audio is incomplete: \(failure, privacy: .public)")
                problems.report(.audioIncomplete(Self.actionable(failure)))
            }
        } catch {
            try? FileManager.default.removeItem(at: encoding.file)
            log.error("keeping the audio failed: \(error, privacy: .public)")
            problems.report(.audioNotKept(Self.actionable(error)))
        }
    }

    /// A stored transcript's kept audio, or nil when none was kept or it is gone.
    func keptAudio(_ transcript: StoredTranscript?) -> URL? {
        TranscriptAudio.kept(transcript?.audio, in: Self.audioFolder)
    }

    func discardLastRecording() {
        lastRecording?.discard()
        lastRecording = nil
    }

}

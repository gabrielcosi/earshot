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
        recording.finish()
        for refinement in refinements { await refinement.value }
        refinements = []
        guard library.selection?.diarization != nil, let endpoint = engine.endpoint,
            let pcm = try? Data(contentsOf: recording.url, options: .alwaysMapped), !pcm.isEmpty
        else { return }
        do {
            let turns = try await Diarizer.diarize(pcm: pcm, engine: endpoint)
            let transcribed = try await Retranscriber.transcribe(
                turns: turns, pcm: pcm, engine: endpoint, allowed: spokenLanguages,
                contexts: rules.speechContexts)
            transcript.relabel(transcribed)
            log.notice(
                "relabelled \(pcm.count / 32_000) s of audio: \(turns.count) turns, \(Set(turns.map(\.speaker)).count) speakers"
            )
            persist()
            translatePending()
        } catch {
            log.error("speaker relabelling failed: \(error, privacy: .public)")
        }
    }

    func clip(at start: Double, seconds: Double) -> Data? {
        lastRecording?.clip(from: start, seconds: seconds)
    }

    /// Encoding an hour takes a while; it runs off the main actor. The audio goes into the
    /// store's folder, never into the transcripts folder.
    func keepAudio(_ recordings: SessionRecordings, for transcript: UUID) async {
        let name = "\(transcript.uuidString).m4a"
        let destination = Self.audioFolder.appending(path: name)
        do {
            let failure = try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                return try recordings.keep(to: destination)
            }.value
            try store.setAudio(name, for: transcript)
            if let failure {
                log.error("kept audio is incomplete: \(failure, privacy: .public)")
                problems.report(.audioIncomplete(Self.actionable(failure)))
            }
        } catch {
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

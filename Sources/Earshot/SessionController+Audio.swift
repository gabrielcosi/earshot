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
            save()
            translatePending()
        } catch {
            log.error("speaker relabelling failed: \(error, privacy: .public)")
        }
    }

    func clip(at start: Double, seconds: Double) -> Data? {
        lastRecording?.clip(from: start, seconds: seconds)
    }

    /// Encoding an hour takes a while; it runs off the main actor.
    func keepAudio(system: Recording, microphone: Recording?, for transcript: URL) async {
        let (systemURL, microphoneURL) = (system.url, microphone?.url)
        let destination = TranscriptAudio.file(for: transcript)
        do {
            try await Task.detached(priority: .utility) {
                try TranscriptAudio.encode(
                    microphone: microphoneURL, system: systemURL, to: destination)
            }.value
        } catch {
            log.error("keeping the audio failed: \(error, privacy: .public)")
            problems.report(.audioNotKept(Self.actionable(error)))
        }
    }

    func discardLastRecording() {
        lastRecording?.discard()
        lastRecording = nil
    }

}

# ADR-0002 — Capture the microphone and system audio as separate channels

- **Status:** Accepted
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Builds on:** [ADR-0001](0001-nemo-speech-as-local-engine.md)
- **Scope:** Audio capture and speaker identity

## Context

In a call, your voice reaches the Mac through the microphone, and everyone else's through the output device. The diarizer assigns anonymous slots in order of first appearance. If both sources were mixed into one stream, "you" would be whichever slot you happened to land in, and the slot would differ from one session to the next.

## Decision

**The microphone and system audio are two streams to the engine.** The microphone stream has diarization off, and every word from it is "Me". The system audio is captured with a Core Audio process tap (`CATapDescription`, macOS 14.2+) in a private aggregate device and has diarization on, so its slots are only the remote participants. The transcript merges both streams by word time.

## Consequences

- "Me" is always correct, with no enrollment and no voice profile.
- The diarizer's eight slots are all available for the remote side.
- **Without headphones, the microphone also picks up the remote audio from the speakers.** That audio is then transcribed twice: once correctly attributed from the tap, and once as "Me". Headphones avoid it, and so does turning off **Include my microphone** when nobody on this Mac speaks, as with a podcast or a video. [ADR-0007](0007-opt-in-echo-cancellation.md) adds echo cancellation as a setting for listening on speakers.
- Two streams run the recognizer twice in parallel.
- The process tap needs the audio-capture permission. macOS ties it to the signing identity, so updates keep it and only a differently signed build asks again.

## Rejected

- **One mixed stream.** It is simpler, but it cannot say which slot is you.
- **ScreenCaptureKit audio.** It works, but it needs the Screen Recording permission, which is broader than audio capture.

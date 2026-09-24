# ADR-0007 — Cancel speaker echo on request, with the process tap as the reference

- **Status:** Accepted
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Builds on:** [ADR-0002](0002-microphone-and-system-audio-as-separate-channels.md)
- **Scope:** The microphone channel when listening without headphones

## Context

Without headphones, the microphone hears the other side of the call through the speakers, about 20 dB under the speakers' own level. Every remote line is then transcribed twice: once from the tap, attributed to its speaker, and once from the microphone as "Me". ADR-0002 accepted this and recommended headphones.

The tap already delivers exactly what the speakers play, resampled to the engine's rate, 90 to 100 ms before the microphone hears it. That is the reference an acoustic echo canceller needs, and the lead is inside the delay WebRTC's AEC3 searches. Measured on a room's speakers with the fixtures as the remote side, AEC3 took the bleed from -28 dBFS to -55 to -58 dBFS, under the room's noise, and the engine transcribed nothing from it; a talker in the room came through, except a phrase trimmed where both talked at once. It costs about 1.3 % of one core.

## Decision

**Echo cancellation is a setting, off by default.** "Cancel speaker echo" in Settings runs the microphone through AEC3 (webrtc-audio-processing 2.1, built into the app as a static library) with the process tap as the far end, before the audio reaches the engine and the kept audio. It exists for people who take calls on speakers. The app still recommends headphones: with them there is no echo, and no processing touches the microphone.

## Consequences

- With the setting on, the remote side stops appearing as "Me". A room talker's words that overlap the remote side exactly can be trimmed.
- Off, nothing changes for anyone: no canceller is created and the microphone is passed through untouched.
- The canceller assumes the microphone and the speakers share a clock, as the built-in ones do. A USB or Bluetooth microphone on its own clock drifts against the tap and cancels worse.
- The app links a C++ library and abseil, built from source by `mise run engine:aec` into `.deps/`.

## Rejected

- **Apple's VoiceProcessingIO.** It cancels only what the same audio unit plays, so it cannot take the tap as reference; fed the room's speakers from another process, its residual was still transcribed in 3 of 8 runs.
- **SpeexDSP's echo canceller.** With the same reference it reached 11 to 16 dB of reduction, and the engine still transcribed most of the residual.
- **Removing duplicates from the transcript.** Two recognizers hear the same speech differently, so matching lines by text is unreliable, and it would still leave the doubled audio in the recording.

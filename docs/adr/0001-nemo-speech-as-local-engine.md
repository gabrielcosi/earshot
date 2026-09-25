# ADR-0001 — Run NeMo-Speech.cpp as a local engine behind its realtime WebSocket

- **Status:** Accepted; the port and the reuse of a running engine superseded by [ADR-0009](0009-an-engine-only-this-launch-can-reach.md)
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Scope:** Where speech recognition and diarization run, and how the app talks to them

## Context

Earshot needs streaming speech recognition in many languages and streaming diarization of up to eight speakers, on-device. NVIDIA's Nemotron 3 Diarization (Sortformer, 100M parameters) and Nemotron 3.5 ASR Streaming (0.6B, about 100 locales) cover both. They ship as NeMo checkpoints and as GGUFs for NeMo-Speech.cpp, NVIDIA's C++ runtime on ggml with a Metal backend.

The two models have to share state: the engine attaches a speaker slot to each word, which needs the diarizer and the recognizer to run on the same audio frames.

## Decision

**The app runs `nemo-speech serve` as a child process on `127.0.0.1:8765` and streams audio to `/v1/audio/transcriptions/realtime`, one WebSocket per capture channel.** The engine loads the ASR model and the diarizer once. The app starts the engine when you start listening, if nothing answers `/ready`, and stops it when the app quits.

## Consequences

- The engine is a separate process. A crash in it ends the current streams, not the app, and the transcript written so far is on disk.
- The engine has its own playground and HTTP API, which are useful for diagnosis without the app.
- The protocol is project-specific, not the OpenAI Realtime API. `EarshotKit` models only the subset the app uses, and the live tests check it against the real engine.
- Defaults that are wrong for live transcription live in `config/server.yaml`. See [engine behaviour](../behaviour.md).

## Rejected

- **Linking the C API into the app.** It needs the engine's C++ build products inside the app bundle and puts a C++ crash in the app process. There is no latency to gain: a commit round trip is about 100 ms.
- **Python NeMo or Transformers.** It needs a Python environment with PyTorch in or next to the app.
- **The ASR on a self-hosted inference server.** It needs the network while listening and sends the audio off the Mac.

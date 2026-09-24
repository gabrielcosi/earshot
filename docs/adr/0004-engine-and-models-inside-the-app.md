# ADR-0004 — Ship the engine inside the app and let the app manage its models

- **Status:** Accepted
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Builds on:** [ADR-0001](0001-nemo-speech-as-local-engine.md)
- **Scope:** What the app bundle contains and where models live at run time

## Context

Earshot is a download: it has to run on a Mac with no build tools, no Python, and no engine installed. The speech models are 810 MB together, and several models do the same job, so the user picks which ones to keep.

## Decision

**The bundle carries the engine; the app downloads and owns the models.**

- The bundle carries `nemo-speech` and its libraries in `Contents/Helpers/nemo-speech/{bin,lib}`.
- `config/server.yaml` and the engine's `models/index.json` go to `Contents/Resources`.
- Models download from Hugging Face into `Application Support/Earshot/Models` in the app's container, in the engine's own cache layout, and are verified against the index's SHA-256 before they are moved into place.
- The app passes the selected model files to the engine with `--asr-model` and `--diar-model`, so the engine never downloads anything itself.

## Consequences

- The app runs on any Apple Silicon Mac with macOS 26.4, with no repository or build tools.
- The model catalog follows the engine version, because the index comes from the same submodule commit as the binary.

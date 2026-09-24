# ADR-0005 — Run the app and its engine in the App Sandbox

- **Status:** Accepted
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Builds on:** [ADR-0004](0004-engine-and-models-inside-the-app.md)
- **Scope:** What the app and the bundled engine may access

## Context

The app captures the microphone and all system audio, downloads models, and runs an engine that parses audio and listens on a local TCP port. Without the sandbox, all of that runs with the user's full file access.

## Decision

**The app is sandboxed, and the engine inherits its sandbox.**

- The app declares `app-sandbox`, `device.audio-input`, `network.client` (model downloads), `network.server` (the engine's port), `files.user-selected.read-write`, and `files.bookmarks.app-scope`.
- The engine declares only `app-sandbox` and `inherit`. macOS kills an inheriting helper that declares anything else.
- Models, preferences, and the engine log live in the container, `~/Library/Containers/com.gabrielcosi.earshot/Data`.
- Transcripts default to the container's `Documents/Earshot`. A folder chosen in Settings is kept as a security-scoped bookmark and accessed for the life of the app.

## Consequences

- Deleting the container removes every file the app created, except transcripts saved to a chosen folder.
- The default transcripts folder is inside the container. Settings shows it and opens it in Finder.
- A new entitlement is a deliberate change to `Support/Earshot.entitlements`, reviewed like code.

## Rejected

- **Running unsandboxed.** Simpler, but a flaw in the engine or the app would reach every file the user can.

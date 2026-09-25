# ADR-0009 — Run an engine only this launch can reach, and that stops with it

- **Status:** Accepted
- **Date:** 2026-09-25
- **Deciders:** gabrielcosi
- **Supersedes:** in [ADR-0001](0001-nemo-speech-as-local-engine.md), the fixed port `127.0.0.1:8765` and using an engine that already answers `/ready`
- **Scope:** How the app starts, finds, and stops the engine

## Context

The app started the engine as a plain child process on port 8765, and used any engine that answered `/ready` there. macOS does not end a child when its parent ends, so a crash or a Force Quit left the engine running, holding about 1 GB and the port. The next launch found it, used it with a new key, and every stream was refused with a 401, shown as "There was a bad response from the server", until the Mac restarted. An engine found this way also kept whatever models it had loaded. A second user on the same Mac, or a second copy of the app, met the same port.

## Decision

**Each launch starts its own engine, on a port the system picks, set to stop when the app stops, and never uses one it did not start.**

- The engine runs with `--port 0`, which binds a free port, and `--exit-with-parent`, which stops it within 50 ms of its parent ending, however the parent ends. It prints its address in its `listener.ready` event once its models are loaded, and the app reads it from there.
- Both options are changes to NeMo-Speech.cpp, kept in `patches/nemo-speech/`, applied by `mise run engine:build`, and offered upstream.
- Each engine gets a key made for it, in its environment.
- The engine's configuration names no models: it loads only the files the app passes, and never downloads one itself. Without a diarization model, it runs without speakers.

## Consequences

- A Force Quit or crash leaves nothing behind, and no launch can meet another launch's engine.
- The patches have to be carried until upstream takes them; an engine update may need them refreshed.
- The app no longer uses `mise run serve`. That engine, on port 8765, is for the playground and the live tests.

## Rejected

- **Checking an existing engine's key and models before using it.** It keeps a path whose only job is deciding whether an engine left by someone else is safe to use.
- **A launcher of our own that ends the engine when the app ends.** Equally robust, without patching the engine, but one more program to build, sign, and ship.
- **Choosing a free port in the app and passing it to the engine.** Another program can take the port between the check and the bind.
- **Running the engine as an XPC service over its C API.** macOS would manage its lifetime, but the app would no longer use the HTTP API the live tests exercise.

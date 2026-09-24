# ADR-0003 — Translate finished utterances with Apple's Translation framework

- **Status:** Accepted
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Builds on:** [ADR-0001](0001-nemo-speech-as-local-engine.md)
- **Scope:** Translation into the user's own language

## Context

Calls and videos mix languages. Recognition stays on `auto`, and a separate "My language" setting (default: the Mac's language) says what to translate into. Anything else should be translated as it is heard.

The engine's realtime finals do not say which language they are in ([engine behaviour](../behaviour.md)).

## Decision

**Each finished utterance is language-detected with NaturalLanguage and, when it is not in "My language", translated with Apple's Translation framework using the low-latency strategy.** Sessions are created with `TranslationSession(installedSource:target:preferredStrategy:)` and cached per language pair. A pair that is supported but not installed raises Apple's download prompt through `translationTask` in the transcript window. Partials are not translated.

Language detection ignores results under 0.5 confidence. Measured on conversational utterances, fillers and jargon score 0.25–0.39 and are often the wrong language, and real phrases of two words or more score 0.74 or higher.

## Consequences

- Translation is on-device, with no extra model to build or download beyond Apple's language packs.
- The translation appears after the utterance ends, not word by word.
- Apple does not support every language the ASR model recognizes. Romanian is transcribed but not translated.
- The deployment target is macOS 26.4, for the view-independent session initializer.

## Rejected

- **The engine's NMT component.** It runs a llama.cpp translation model, which is another model to download, serve, and keep in memory next to the two speech models.
- **Translating partials.** They change with every chunk, and each change would be a new translation request.

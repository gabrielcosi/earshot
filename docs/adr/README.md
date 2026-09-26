# Architecture Decision Records

Decisions of consequence for Earshot. Each record states the context that forced a decision, the decision itself, what it costs, and what was rejected.

Records are immutable once accepted. A decision that changes gets a new record that supersedes the old one; the original stays as written.

## Index

| #                                                                | Title                                                                     | Status   |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------- | -------- |
| [0001](0001-nemo-speech-as-local-engine.md)                      | Run NeMo-Speech.cpp as a local engine behind its realtime WebSocket       | Accepted |
| [0002](0002-microphone-and-system-audio-as-separate-channels.md) | Capture the microphone and system audio as separate channels              | Accepted |
| [0003](0003-apple-translation-per-utterance.md)                  | Translate finished utterances with Apple's Translation framework          | Accepted |
| [0004](0004-engine-and-models-inside-the-app.md)                 | Ship the engine inside the app and let the app manage its models          | Accepted |
| [0005](0005-app-sandbox.md)                                      | Run the app and its engine in the App Sandbox                             | Accepted |
| [0006](0006-direct-download-with-sparkle.md)                     | Ship as a notarized direct download that updates itself with Sparkle      | Accepted |
| [0007](0007-opt-in-echo-cancellation.md)                         | Cancel speaker echo on request, with the process tap as the reference     | Accepted |
| [0009](0009-an-engine-only-this-launch-can-reach.md)             | Run an engine only this launch can reach, and that stops with it          | Accepted |
| [0008](0008-choose-which-apps-to-transcribe.md)                  | Choose which apps to transcribe, per session                              | Accepted |
| [0010](0010-a-transcript-store-with-markdown-as-export.md)       | Keep transcripts in a SQLite store and write Markdown as a one-way export | Accepted |
| [0011](0011-captions-overlay-as-an-appkit-panel.md)              | Float captions over other apps in an AppKit panel, seen by screen shares  | Accepted |

## Reading order

[0001](0001-nemo-speech-as-local-engine.md) establishes the engine, and [0009](0009-an-engine-only-this-launch-can-reach.md) how each launch runs its own; everything else assumes them. [0002](0002-microphone-and-system-audio-as-separate-channels.md) covers capture and speaker identity, [0007](0007-opt-in-echo-cancellation.md) what happens to the microphone without headphones, and [0008](0008-choose-which-apps-to-transcribe.md) which apps the system channel holds. [0003](0003-apple-translation-per-utterance.md) covers translation, and [0010](0010-a-transcript-store-with-markdown-as-export.md) where transcripts are kept and what is written to the transcripts folder. [0011](0011-captions-overlay-as-an-appkit-panel.md) covers the captions overlay over other apps. [0004](0004-engine-and-models-inside-the-app.md) covers what the app bundle contains, [0005](0005-app-sandbox.md) what it may access, and [0006](0006-direct-download-with-sparkle.md) how it ships.

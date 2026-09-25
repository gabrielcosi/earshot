# AGENTS.md: earshot

A macOS menu-bar app that transcribes calls, meetings, videos, and anything else the Mac plays, on-device. It separates the speakers and translates what is not in your language. Speech runs in NVIDIA's NeMo-Speech.cpp on Metal; translation runs in Apple's Translation framework.

- Architecture decisions: `docs/adr/`. Read [ADR-0001](docs/adr/0001-nemo-speech-as-local-engine.md) first. It establishes the engine and how the app talks to it; everything else assumes it.
- What the engine, Core Audio, and Apple's frameworks actually do: [docs/behaviour.md](docs/behaviour.md). Read it before you change anything on the WebSocket, in `config/server.yaml`, or in `SystemAudioCapture`. Several engine defaults are wrong for live transcription.

## Code standard

Write Swift that is idiomatic, DRY, and properly unit and live tested.

- Swift 6.2+ tools in Swift 6 language mode. The app target uses `defaultIsolation(MainActor)`. Audio capture types are `nonisolated`, because their callbacks run on Core Audio and AVAudioEngine threads, and a MainActor-inferred closure there traps on the executor check.
- Swift Testing (`@Test` / `#expect`). No XCTest in new code.
- `@Observable` plus `@Environment` for state and injection. No `ObservableObject`, no DI container, no protocol-per-service unless there are two production implementations.
- Platform-agnostic logic goes in `EarshotKit`: the WebSocket protocol and client, the transcript model, language detection, and export. SwiftUI, AppKit, Core Audio, AVFoundation, and Translation stay in the app target. The module boundary is the check: if something in `EarshotKit` wants AppKit, it is in the wrong place.
- Capture (Core Audio, AVFoundation) lives in `EarshotCapture`, so it can be tested apart from the app. `CEchoCanceller` is the C face of WebRTC's AEC3 for it.
- Configuration comes from `Support/Info.plist` and the bundle's resources. `ProcessInfo` environment is a test seam (`EARSHOT_LIVE`), never runtime config.

## Tooling

`mise` pins the versions and owns the commands; `lefthook` runs them on commit and push. `mise install` sets up both, and installs the hooks as a postinstall step. Nothing goes to Homebrew or `~/Library/Caches`: the engine and its SentencePiece dependency build into `.deps/`, and `NEMO_SPEECH_MODEL_DIR` points the model downloads at `models/`. The Swift toolchain comes from Xcode and mise cannot pin it. Xcode 27 / Swift 6.4 is what everything here was verified against.

| Command                  | Does                                                                             |
| ------------------------ | -------------------------------------------------------------------------------- |
| `mise run engine:build`  | Build SentencePiece, the echo canceller, and `nemo-speech` (Metal) into `.deps/` |
| `mise run engine:aec`    | Build webrtc-audio-processing (WebRTC AEC3) with its abseil into `.deps/`        |
| `mise run engine:models` | Download the ASR and diarization GGUFs into `models/`                            |
| `mise run serve`         | Run the engine in the foreground on `127.0.0.1:8765`, with the playground        |
| `mise run build` / `run` | Bundle `build/Earshot.app` / and open it                                         |
| `mise run fmt`           | Format Swift sources in place                                                    |
| `mise run lint`          | `swift format lint` then `swiftlint`, neither modifying anything                 |
| `mise run test`          | The hermetic suite                                                               |
| `mise run test-live`     | The engine-backed layer; needs `mise run serve`                                  |
| `mise run test-capture`  | The real process tap; plays sound, needs audio-capture permission                |
| `mise run dead-code`     | Fail on unused declarations                                                      |
| `mise run check`         | What gates a change: `lint`, `test`, `dead-code`                                 |

**swift-format owns layout, SwiftLint owns safety and logic.** Every SwiftLint rule about whitespace, line breaks, or commas is disabled in `.swiftlint.yml` so the two cannot disagree. Both are clean, with no baseline and no suppressions. A violation is a thing to fix, not a rule to switch off. If a rule is wrong for this codebase, disable it in `.swiftlint.yml` with the reason written down.

Dead code is a gate on **pre-push**, because Periphery needs a full build. It runs `swift build --build-system native`: the default Swift Build backend writes no index store where Periphery looks for one. `--retain-codable-properties` keeps the `Encodable` request fields, which only the encoder reads.

## Git

- Conventional Commits, all lowercase: `type(scope): imperative description`.
- Commit through mise, `mise x -- git commit`. The hooks call swift-format, SwiftLint, and oxfmt, which are only on mise's PATH.
- Push every commit right after it is made: `mise x -- git push origin main`. The pre-push hook runs the tests and the dead-code scan.
- Nothing is installed outside the repository. No Homebrew, no global caches: a new tool goes into `.mise/config.toml`, a new library builds into `.deps/`.
- Build and release logic lives in mise tasks in `.mise/config.toml`, not in shell scripts. `scripts/` holds only `fixtures.sh`, which embeds Python.

## How to work on this

### Before fixing a bug, find the root cause

Not a guess that makes the symptom go away. Reach for evidence early: `log stream --predicate 'subsystem == "com.gabrielcosi.earshot"'`, the engine log at `~/Library/Containers/com.gabrielcosi.earshot/Data/Library/Logs/Earshot-engine.log`, the playground at <http://127.0.0.1:8765/>, or a live test that measures the thing.

**Then write the failing test before the fix**, and run it against the unfixed code. A test that passes on broken code proves nothing. State the before and after in the handoff.

### No unexplained constants

A timeout, threshold, or buffer size must be justified by something: a measured figure, a documented limit, or a protocol requirement. Each one here says where its number comes from (`startupTimeout`, `commitTimeout`, `minimumConfidence`, `tapFrames`, `engineChunkBytes`). If a number cannot be justified, it is hiding a bug.

### Comments

Only where they carry what the code cannot:

- Surprising engine, Core Audio, or SDK behaviour that is not visible at the call site.
- Something that looks wrong but is deliberate, especially "we tried X, it failed because Y".
- Rationale someone would otherwise reverse.
- Cross-references outside this repo.

Not for restating the code. If a block needs a comment to be followed, it usually needs a better name or to be smaller.

### Tests

Three layers, each covering what the one below cannot:

| Layer   | Command                 | Covers                                                                                                                                                                                                                                                      |
| ------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unit    | `mise run test`         | Protocol encoding and decoding, transcript assembly, language detection, export, capture conversion (tap-shaped buffers at 44.1 and 48 kHz must come out as 16 kHz at the same pitch), and echo cancellation on synthetic echo. Hermetic and a few seconds. |
| Live    | `mise run test-live`    | The engine: endpointing, diarization, and language switching, streamed at real-time pace from `Tests/EarshotKitTests/Fixtures/`; and that cancelled echo transcribes to nothing.                                                                            |
| Capture | `mise run test-capture` | The real process tap: plays a clip and captures it at real-time rate. Makes sound and needs the audio-capture permission for Terminal.                                                                                                                      |

The live layer streams at real-time pace on purpose. Endpointing depends on it: streamed five times faster, the same clip comes back as a single final. The fixtures are `say` voices generated by `mise run fixtures`. They are cleaner than real people and do not overlap, so a pass here is necessary, not sufficient. The microphone has no automated test: driving it needs a virtual input device, which means installing an audio driver. Its conversion shares the resampler the unit tests cover, and the tap it rebuilds after a configuration change is unit tested; the restart itself is checked by hand, by starting a FaceTime call while listening.

## Layout

```
Sources/
  EarshotKit/          protocol, WebSocket client, transcript, language detection, export
  EarshotCapture/      process tap, microphone, resampler, echo canceller, audio encoder for kept audio
  CEchoCanceller/      C interface over webrtc-audio-processing's AEC3
  Earshot/             menu-bar app: capture, engine supervisor, translation, SwiftUI
Tests/EarshotKitTests/
  Fixtures/            generated speech clips for the live layer
Support/               Info.plist, entitlements, app icon, menu bar glyphs
config/server.yaml     engine configuration
scripts/               fixtures.sh
vendor/NeMo-Speech.cpp engine source (submodule)
patches/nemo-speech/   Earshot's changes to the engine, applied by engine:build
docs/adr/              product decisions
docs/behaviour.md      engine, Core Audio, and framework behaviour established by experiment
```

## Running it

Setup, tasks, dependency updates, and releases are in [CONTRIBUTING.md](CONTRIBUTING.md).

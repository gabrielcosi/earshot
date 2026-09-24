# Contributing

Earshot is a Swift package with no Xcode project. [mise](https://mise.jdx.dev) pins every tool and runs every task, and nothing is installed outside the repository. How the code is written and tested is in [AGENTS.md](AGENTS.md).

## Build

You need an Apple silicon Mac with macOS 26.4 or newer, Xcode, and mise.

```sh
git submodule update --init
mise install
mise run engine:build    # the speech engine and the echo canceller, built from source into .deps/
mise run engine:models   # the models the live tests and `mise run serve` use
mise run run             # build Earshot.app and open it
```

`mise run build` signs ad hoc unless `EARSHOT_SIGN_IDENTITY` names a signing identity. Set it in `.mise/config.local.toml`, which is gitignored: with ad hoc signing every rebuild is a new app to macOS, and it asks for the microphone and audio-capture permissions again.

## Tasks

| Task                         | What it does                                                                     |
| ---------------------------- | -------------------------------------------------------------------------------- |
| `mise run serve`             | Run the speech engine in the foreground, with its playground in the browser      |
| `mise run test`              | Unit tests; hermetic and sub-second                                              |
| `mise run test-live`         | Tests against the engine started by `mise run serve`                             |
| `mise run test-capture`      | Capture this Mac's audio through the real process tap; plays sound               |
| `mise run lint`              | swift-format and SwiftLint, strict                                               |
| `mise run check`             | Lint, unit tests, and the dead-code scan                                         |
| `mise run verify`            | Check, rebuild the engine, and run the live tests against it; quit Earshot first |
| `mise run build`             | Build `build/Earshot.app`                                                        |
| `mise run release <version>` | Build a notarized DMG and add it to the update feed                              |
| `mise run publish <version>` | Tag the release and publish it on GitHub                                         |

## Dependency updates

Renovate opens pull requests on Forgejo: development tools once a month, Sparkle and webrtc-audio-processing as they release, and the engine weekly. Nothing merges on its own, because no CI runs here. Check out each one and run `mise run verify` before merging. A webrtc-audio-processing update also needs the commit pinned under its version in the `engine:aec` task, which Renovate does not know.

The app downloads the models the engine's `models/index.json` pins, except where `ModelCatalog.overrides` substitutes a newer file. Each override names the revision it replaces and lapses when the index pins anything else; `mise run test` then fails until the override and the revision in the `engine:models` task are removed.

## Releasing

Releases are notarized DMGs on GitHub Releases, and the app updates itself with Sparkle ([ADR-0006](docs/adr/0006-direct-download-with-sparkle.md)). A release Mac needs, once:

- a Developer ID Application certificate in the login keychain, named in `EARSHOT_RELEASE_IDENTITY` in `.mise/config.local.toml`;
- notary credentials: `xcrun notarytool store-credentials earshot --apple-id <email> --team-id <team>`;
- the Sparkle signing key in the login keychain under the `earshot` account. `generate_keys --account earshot -x <file>` exports a backup, and `-f <file>` imports it on another Mac.

Release notes go in `docs/releases/<version>.md`. Then, from a clean commit on `main`:

```sh
mise run release 0.2.0   # --rehearse skips notarization, to try it with a development identity
mise run publish 0.2.0
```

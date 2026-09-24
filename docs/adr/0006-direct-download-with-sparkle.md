# ADR-0006 — Ship as a notarized direct download that updates itself with Sparkle

- **Status:** Accepted
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Builds on:** [ADR-0005](0005-app-sandbox.md)
- **Scope:** How releases are built, published, and installed

## Context

Earshot captures every app's audio through a Core Audio process tap and runs a bundled engine that listens on a local port. Gatekeeper refuses an app from the internet unless it is signed with a Developer ID and notarized by Apple. Without an updater, every fix waits for users to download a new copy by hand.

## Decision

**Releases are Developer ID signed, notarized DMGs on GitHub Releases. The app updates itself with Sparkle.**

- The source lives on Forgejo. A push mirror copies it to GitHub, which hosts the releases.
- The app and the DMG are both notarized and stapled, so they open offline. Each update is signed with an EdDSA key, and Sparkle refuses one whose signature does not match.
- Every release carries the appcast, so `releases/latest/download/appcast.xml` is always the current feed.
- Sparkle runs sandboxed: its installer launches through `SUEnableInstallerLauncherService`, reached through the `-spks` and `-spki` mach-lookup exceptions. Downloads use the app's own `network.client` entitlement.
- The EdDSA private key lives in the release Mac's login keychain, under the `earshot` account. Losing it means no update can reach existing installs.

## Consequences

- Releases need the paid Apple Developer Program for the Developer ID certificate and notarization.
- Releases are built on a Mac, by hand. The EdDSA key and the Developer ID key never leave its keychain.
- The bundle identifier `com.gabrielcosi.earshot` cannot change after the first release: macOS ties the sandbox container, the keychain items, and the privacy permissions to it.

## Rejected

- **The Mac App Store.** The process tap and the bundled engine listening on a port make review uncertain, and releases would wait on it.
- **Releases on Forgejo.** GitHub serves downloads from a CDN, and users find the project there.
- **Releasing from CI.** No macOS runner exists, and CI would need both private keys as secrets.

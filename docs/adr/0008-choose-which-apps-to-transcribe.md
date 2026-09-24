# ADR-0008 — Choose which apps to transcribe, per session

- **Status:** Accepted
- **Date:** 2026-09-24
- **Deciders:** gabrielcosi
- **Builds on:** [ADR-0002](0002-microphone-and-system-audio-as-separate-channels.md), [ADR-0007](0007-opt-in-echo-cancellation.md)
- **Scope:** Which of the Mac's audio the system channel holds

## Context

The system channel taps every app. Music or a video playing next to a call is transcribed with the call and diarized as more speakers. Core Audio can tap a list of processes instead of the whole Mac, and it lists the processes that have audio and whether each is playing.

Apps rarely play from their own process. Chromium and Electron apps play from a helper the app launched. WebKit apps play from a media process launchd starts, one per app ("Safari Graphics and Media"). Browsers play every tab from one process, and apps restart their audio helpers, for example when a call begins.

## Decision

**"Listening to" in the menu picks the apps to transcribe from those playing sound. The default, and every launch, is all apps.**

- A source is what macOS registers as a running app: a helper is grouped under the first app up its parent chain. A process no app launched, such as a WebKit media process, goes to the running app whose whole name starts its name ("Safari Graphics and Media" plays for Safari), and stands for itself when there is none. macOS has no public way to ask which app such a process works for. System daemons that keep an output open and command-line tools are not offered.
- A source is stored as the owning app's bundle identifier, not a process. The tap is rebuilt whenever the processes behind the chosen apps change, and while none of them runs, the system channel captures nothing.
- The choice can change while listening; the tap is rebuilt in place, as on an output-device change.
- With echo cancellation on, a second tap of every app is the canceller's reference, so sound from apps that are not transcribed still leaves the microphone.
- The choice is not kept between launches: a launch never waits silently for an app that is gone.

## Consequences

- Two tabs in one browser cannot be separated: a call in one tab and music in another are one source. A call and music in different apps or browsers can.
- The media process's name is WebKit's, so matching it depends on its wording. Where a language puts the app's name elsewhere, the source shows under the process's full name; it never shows under a wrong app.
- With echo cancellation on, two taps run; a tap costs little next to the recognizer.

## Rejected

- **Per-tab capture.** Core Audio separates processes, not tabs.
- **The private responsibility call** (`responsibility_get_pid_responsible_for_pid`), which other per-app audio tools use. It names the app reliably, but it is undocumented and can change with any macOS release.
- **Tapping by bundle identifier** (`CATapDescription.bundleIDs`, macOS 26). Measured: tapping `com.apple.Safari` while Safari played a video delivered nothing, and `com.apple.WebKit.GPU` delivered every WebKit app's sound at once.
- **Remembering the choice.** An app chosen yesterday and not running today would leave the system channel silent with nothing on screen to say why.

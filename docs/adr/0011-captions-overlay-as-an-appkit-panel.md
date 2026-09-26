# ADR-0011 — Float captions over other apps in an AppKit panel, seen by screen shares

- **Status:** Accepted
- **Date:** 2026-09-26
- **Deciders:** gabrielcosi
- **Scope:** The captions overlay: what kind of window it is, and what it promises about screen sharing

## Context

The captions overlay shows the last few lines over any app while listening, including a call in full screen. It must never take focus from the call: typing stays in the call's chat while the overlay is clicked, moved, or resized.

SwiftUI's window scenes offer a floating level, but not the window behaviour this needs: joining every Space and full-screen Spaces (`NSWindow.collectionBehavior`), or a window that takes clicks without activating its app (`NSWindow.StyleMask.nonactivatingPanel`). A floating panel of a regular app, which Earshot is while its window is open, is not shown over another app's full-screen Space unless it is non-activating ([behaviour](../behaviour.md#appkit-floating-panels)).

Apple documents `NSWindow.SharingType.none` as "a legacy constant that macOS no longer uses" and says not to use it "to hide or omit content from being captured". ScreenCaptureKit captures such windows, and no public API tells an app that the screen is being shared.

## Decision

**The overlay is an `NSPanel` hosting SwiftUI content. It is a window like any other to screen sharing.**

- The panel is titled with its title bar hidden, for the system's shadow, corners, and edge resizing. It is non-activating, cannot become key or main, floats, joins all Spaces and full-screen Spaces, and is ordered front without activating Earshot. It is not counted with Earshot's windows, so it adds no Dock icon.
- It takes clicks: it is dragged by its text or background and resized from its edges, and its controls work, all without activating Earshot. The controls are left out of the drag, and are drawn as active although the panel never becomes key. Its height decides how much it shows, down to the live line and the line before it; its frame is remembered. Clicks do not pass through to the app behind it.
- It shows while listening and hides when the user stops. A session that ends on its own, or fails to start, leaves it showing why, with the fix, until ✕ or the next start. ✕ hides it for the rest of the session; the setting stays on.
- The text sits on the dark HUD material, whatever the system appearance, to read over bright video. Liquid Glass is only on its controls.
- `sharingType` is not set. Settings says people see the overlay when the whole screen is shared, and that sharing a single window keeps it private.

## Consequences

- Anyone who sees a whole-screen share sees the captions.
- VoiceOver reaches the overlay only through its window chooser, as the panel never becomes key; the main window's live lines are the VoiceOver path.
- With "Displays have separate Spaces", the overlay stays on its display; the user drags it to the call's display once, and its frame is remembered. A frame saved on a display that is gone opens at the bottom centre of the main screen.

## Rejected

- **A SwiftUI `Window` scene.** It cannot join another app's full-screen Space, and clicking it activates Earshot.
- **Hiding the overlay from screen sharing** with `sharingType = .none`. Some capture apps would hide it and others show it, so a user could not know in advance; Apple says not to use it for this.
- **Clicks through the text to the app behind.** macOS has no per-region click-through; it needs a Mac-wide mouse monitor.

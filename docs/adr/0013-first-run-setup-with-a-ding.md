# ADR-0013 — A first-run setup window that checks system audio with a ding

- **Status:** Accepted
- **Date:** 2026-09-27
- **Deciders:** gabrielcosi
- **Scope:** What Earshot shows at first launch, when it asks for permissions, and how it checks that it can hear the Mac

## Context

Until 0.2, a launch without a model opened **Settings > Models**, and nothing else explained Earshot. The permissions were asked for at the first start, in the middle of a call.

System Audio Recording has no public API to ask for it or to read it. macOS asks the first time an app starts an aggregate device holding a process tap, and a tap Earshot may not use delivers exact zeros with no error from any call. A session without the permission looks as if it works, with a flat system meter. A grant reaches only a tap built after it. Comparable apps either do not capture the Mac's audio, only tell users to check the setting, or read the permission through private TCC functions.

## Decision

**A separate setup window opens at first launch. It downloads the models on request, asks for the microphone from its own button, and checks System Audio Recording by playing a ding through the tap sessions use.**

- It is a `Window` scene, not a sheet: at first launch there is no window to hang a sheet on. While it is open Earshot is in the Dock and ⌘Tab, as with its other windows.
- Eight pages, each with its own illustration. Every choice on them is the same setting as in Settings and the menu, shown as it is; the illustrations never change a setting.
- The download starts only from its button, after a free-space check, and continues in the background.
- **Play the Ding** starts the global tap every session uses, which includes Earshot, plays the system's Glass sound in Earshot once the tap delivers, and listens until it hears anything or the sound ends. Any sample that is not zero means Earshot may listen; only zeros mean it may not. When the permission prompt took Earshot's focus during the check, the check runs once more when Earshot is active again; otherwise **Try Again** and **Open System Settings** are offered. The ding is disabled while a session runs.
- Refusing the microphone from setup's button turns **Include my microphone** off, and the page says so.
- Closing the window finishes setup. Quitting midway shows it again at the next launch. Users of an earlier Earshot, who have a model or transcripts, are marked done without seeing it. Without a model, a launch opens it at the models page. **Show Welcome…** in Settings runs it again.

## Consequences

- The first press of **Play the Ding** plays it into a tap that cannot hear it yet, behind the permission prompt; the user hears the ding twice when the check repeats.
- The check says nothing about a permission revoked later; a session then still looks as if it works.
- The ding is audible, at the output's volume, and the recording indicator shows for the second the tap runs.

## Rejected

- **Private TCC functions** to read the permission: undocumented, and reported unreliable.
- **A muted tap of Earshot's own process**, for a silent check: it is not known to need the same permission, and it is not the tap sessions use.
- **Showing setup to earlier users**: they have models and permissions, and it would stand between them and the call they opened Earshot for.

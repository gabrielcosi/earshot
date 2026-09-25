# ADR-0010 — Keep transcripts in a SQLite store and write Markdown as a one-way export

- **Status:** Accepted
- **Date:** 2026-09-25
- **Deciders:** gabrielcosi
- **Supersedes:** in [ADR-0005](0005-app-sandbox.md), the transcripts folder as where transcripts live; it is now where their Markdown copies are written
- **Scope:** Where transcripts, names, summaries, translations, and kept audio are stored, and what Earshot writes to the transcripts folder

## Context

Earshot kept each transcript as a Markdown file in the transcripts folder, rewritten from memory after every finished line, and read the files back for the window, naming, and summaries. Several paths rewrote a file from an older copy. A late translation, a changed word rule, or a relabel re-rendered the session and reverted notes the user had added in another editor. A summary read the file, waited up to a minute for the model, and wrote back what it had read. After the transcripts folder changed, the session in memory was written into the new folder. Kept audio sat next to the file as an `.m4a`. Editing lines, keeping the original next to the edits, and syncing between Macs all need more than a text file can hold.

## Decision

**Every transcript lives in one SQLite database in the container, `Application Support/Earshot/Earshot.sqlite`. The Markdown file is a copy written from it, never read back.**

- The store uses [GRDB](https://github.com/groue/GRDB.swift), pinned to an exact version, against macOS's own SQLite. The app opens a `DatabasePool` (WAL), so the window reads while a session writes; tests use an in-memory `DatabaseQueue`. The schema changes only through registered `DatabaseMigrator` migrations.
- What was heard is the original and does not change once the session ends. A transcript's row is created with its first finished paragraph, and each final writes the session's paragraphs in one transaction, so a crash loses no finished line. At launch, a transcript a crash left open is sealed where its last paragraph ends, and every transcript without a Markdown file gets one.
- Names, the latest summary, translations, and edits are stored beside the original. A translation belongs to a paragraph and the hash of the text it was made from, and shows only while that text is current. Edits are the current state of each paragraph (its text, its speaker, or that it is left out), not a log; the window's undo sets back the previous state. Word rules are not stored: they apply wherever text is shown or written.
- Renaming a speaker also renames the old label wherever the summary mentions it. A summary is written against the names as they are when it lands, so a rename made while it was being written is kept.
- The Markdown file is written when a session ends and again after naming, a summary, a late translation, or an edit, in the format earlier versions wrote. Exports of one transcript run one at a time; changes made while one runs are written by one more.
- Earshot writes over its file only while the file is byte for byte what it last wrote there, which it checks against a stored SHA-256. A file changed outside Earshot is left as it is, and one that was moved or deleted is not written again. Both show as stale, with **Export…**, which writes a new copy through the save panel; a copy saved in the transcripts folder becomes the one kept up to date. A transcript's first file never replaces a file already there: it gets a numbered name instead.
- After the transcripts folder changes, a transcript's next export creates a new file in the new folder. Files in the old folder are left where they are.
- Kept audio is `Audio/<transcript id>.m4a` in the same container folder, and is not copied into the transcripts folder. The window offers **Show Audio in Finder** and **Export Audio…**. The temporary recording a session needs until its speakers are named stays in Caches, as before.
- The schema is ready for iCloud sync through CKSyncEngine, which comes later and opt-in. Every table has a UUID primary key of its own and no other unique constraint, since CloudKit enforces none; foreign keys cascade; columns added later are nullable or have a default. Where a transcript was exported on this Mac is in `local_export`, which is never synced.

## Consequences

- Transcripts no longer live in the transcripts folder. Editing a Markdown file changes nothing in Earshot, and deleting one does not delete the transcript.
- Transcripts from 0.1 are Markdown files that the store does not have. They are brought in once, on first launch, by a migration that reads them and never writes to or deletes them.
- Deleting the container deletes every transcript and its kept audio. The Markdown copies in a chosen folder stay.
- A change to a word rule reaches a transcript's file at its next export, not at once.
- The shipped executable, stripped, grows from 2.5 MB to 5.7 MB, measured on release builds before and with the store.

## Rejected

- **Markdown as the source of truth.** Every path that rewrites a file from memory can revert a change made outside Earshot, and a file cannot hold edits beside the original, timed words, or per-paragraph translations.
- **Reading changes back from Markdown.** Two sources of truth need a merge, and a file edited by hand does not keep the structure the store needs.
- **Recreating a deleted export.** A deleted file is most often one the user meant to delete.
- **SwiftData or Core Data.** Sync through them ties the schema to their CloudKit mirroring; GRDB leaves the records and CKSyncEngine under Earshot's control, and runs the same in tests without a container.

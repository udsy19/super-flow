# Changelog

All notable changes to Super Flow are recorded here. The format follows Keep a Changelog; versions follow SemVer.

## [Unreleased]

## [1.0.0] - 2026-10-19

### Added
- Dictation into any app: hold Fn (push-to-talk), Fn+Space or double-tap Fn (hands-free with live text), with a
  300 ms pre-roll, 150 ms post-roll, streaming recognition while the key is held, and a 20-minute session limit.
- Local speech: Parakeet TDT 0.6B v3 on the Neural Engine (25 languages), Whisper as the multilingual fallback and
  the Intel engine, Silero VAD bundled with the app.
- Cleanup with the local Qwen3.5 model inside a wall-time budget and deterministic rules around it: fillers,
  self-corrections, numbers, lists, spoken commands, per-app style, style detection, snippets, dictionary spellings,
  and guardrails that fall back to the rules-only text. "Undo AI edit" in History.
- Dictionary with replacement rules and auto-learn from edits; snippets with use counts; styles per app category.
- Command Mode (Fn+Control) and Transforms (⌥1 Polish, ⌥2/⌥3 custom prompts) over selected text.
- Meeting Notetaker: detection of calls in Zoom, Teams, Meet, Slack, Webex, Discord, WhatsApp and FaceTime with a
  "Record?" prompt ("Don't ask for this app" remembered), two-track recording, live transcript, speaker split, notes
  with decisions and action items from Qwen3.5-4B, markers, Markdown export, 30-day audio retention, crash recovery.
- The Flow Bar: every dictation and meeting state, "Getting ready… N%" while a model downloads, cards for every
  failure with the fix, the meeting prompt, hide for an hour, dock to any edge.
- The hub: Home and History, Dictionary, Snippets, Style, Notes (stored in the database), Meetings with summary,
  transcript and notes tabs, Settings, onboarding and permission screens.
- Automatic background model downloads (speech first, unmetered networks only, paused while busy), with resume,
  SHA-256 and pinned repository revisions; import, pause, delete and disk usage in Settings › Models.
- Background updates from GitHub Releases, verified by SHA-256 and code signature.
- Our own cue sounds (`scripts/make-sounds.swift`), `superflow://` URLs, a one-line installer and a DMG.
- A headless self-test suite, including an end-to-end run of the real engines on synthetic speech.

### Fixed
- The store never crashes the launch or sets data aside without need: a damaged database, or one whose schema can't be
  migrated, goes to Backup and every row that can still be read is copied into the fresh store; a database that is
  merely busy, read-only or on a full disk is left untouched and the session runs in memory, with a card saying so.
  Migration steps commit atomically, and a full disk is reported as "Storage Full".
- A meeting is never "no recording found": audio whose row was lost becomes "Recovered recording from …" instead of
  being deleted, and the next launch says which recording it recovered. Final audio files are encoded chunk by chunk
  into a temporary file that atomically replaces the old one before any chunk is deleted, so an interrupted finalize
  can't lose audio; deleting a meeting removes its audio before its row. A child process killed with SIGKILL
  mid-meeting is recovered in the self-test.
- Meetings stop by themselves before the disk fills (and don't start without room), keeping everything recorded;
  stop properly when the Mac sleeps or the user session switches; save the transcript when Super Flow quits; restart a
  microphone that went quiet (unplugged, switched) and say so when it stays quiet; and say when only the microphone is
  being recorded because system audio isn't allowed.
- Utterances the speech engine failed on during a meeting are transcribed again from disk afterwards; a meeting page
  with no transcript offers "Retry transcript" from the saved audio, and one without a summary offers "Generate
  summary" instead of saying the meeting was too short.

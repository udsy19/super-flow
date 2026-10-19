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
- A second dictation engine: NVIDIA Nemotron Speech Streaming EN 0.6B through FluidAudio, chosen in Settings › Models
  as "Nemotron (English, fastest, live text)". It recognises while the key is held, shows live text, and has the final
  text about 20 ms after key-up; English only, so other languages and meetings stay on Parakeet. The NVIDIA Open Model
  License ships with the app. On macOS 26, Apple's on-device SpeechAnalyzer is a zero-download choice for one language.
- Quick note on the Flow Bar: hover the bar and click the note button to open Notes with a blank note ready for
  dictation (a second click reuses it while it is still empty). The bar's hover buttons are now Open Super Flow,
  Quick note and sounds: the dictation language is chosen in Settings, and the Notetaker starts from its shortcut or
  the hub.
- A "Cleanup model" choice on Macs with 24 GB or more: Qwen3.5 2B (the default) or Qwen3.5 4B (best quality).
- The cleanup evaluation set (`docs/specs/cleanup-eval.jsonl`, 222 dictations) runs in the self-test: the rules alone
  must keep 207 passes, and with the dev model the rules and Qwen3.5-2B must pass 90% (they pass 93.7%).

### Fixed
- The Flow Bar follows the Dock: it sits 14 pt above the Dock at any size, at the bottom edge of the screen when the
  Dock is on a side or hidden, and drops to the bottom edge in a full-screen app (Split View included), gliding
  between the two as the space, the app in front, the displays or the Dock's settings change.
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
- Dictated words are never lost. Audio goes to disk from the first frame (`Audio/Dictations/<id>.pcm`), so a crash,
  force quit or power loss leaves a History row at the next launch ("Recovered an interrupted dictation") instead of
  nothing; a self-test kills a dictating child process with SIGKILL and gets the words back. An engine failure, or a
  cancel after speaking, keeps the audio as a History row, and every row with audio offers "Retry transcript". The
  long-dictation sample buffer no longer sits in memory.
- A paste that lands nowhere gives the user's own clipboard back instead of replacing it; the card says "Click a
  textbox and use ⌃⌘V to paste" and its Copy button puts the words on the clipboard. A dictation History can't save
  (a full disk) still pastes with ⌃⌘V and says why; so does one made with History turned off.
- A microphone unplugged mid-dictation finishes the dictation with what was heard instead of listening to nothing; a
  cleanup model that is installed but won't load says so once while dictation carries on with the rules.
- Audio files are read to the end: a single read stopped at the last whole 1024-frame packet and dropped the tail.
- Every local-LLM call has a hard wall-clock limit: a hung model, a long prefill, or a model busy with meeting notes
  can no longer hold a dictation; it gets the rules-only text within half a second of its budget, and Transforms and
  notes fail with "timed out" instead of waiting for minutes. A cleanup that leaves out part of what was said (a
  dropped clause the length check alone accepted) is rejected in favour of the rules text.
- A speech model that is installed but won't load (a damaged file) no longer fails every dictation: the next installed
  model is tried, and a card says whether dictation is running on another model or can't start until it's fixed.
- Notes and meeting notes typed just before quitting are saved: the pause-before-saving editors save at once when the
  app quits. A meeting note or a dictionary star that can't be saved says so instead of failing silently.
- A microphone that is unplugged, or won't restart after a format change, hands capture to the system default input
  instead of leaving the recording silent.
- Meeting audio retention never deletes audio that is a meeting's only record (nothing was transcribed), so "Retry
  transcript" keeps working; the meeting page no longer shows an expiry date for it.
- A second running copy of Super Flow (a development build beside the installed app) never finishes, moves or deletes
  a dictation or meeting the other copy is still recording: recordings hold a lock that launch recovery respects, and
  the kernel releases it the moment a process dies.
- Cleanup corrections that hold: self-corrections resolve at every cleanup level, also across the commas speech
  engines write ("No, wait,"), with "make that", "I meant" and "no, sorry"; a mid-sentence "scratch that" takes back
  only the clause before it instead of the whole sentence. Spoken flags, slashes and file names become symbols in
  terminals and AI apps ("dash dash save dash dev" → `--save-dev`, "config dot yaml" → `config.yaml`); French,
  German, Spanish, Italian, Portuguese and Dutch fillers go; digits read one by one become one number ("123 Main
  Street", "555-123-4567", "$100", "$1.2 million", "2.4.1", "404") instead of "one 23"; dictionary words heard as
  sound-alikes ("Shivon", "cube control", "postgres QL") are spelled as in the dictionary; Medium cleanup lists short
  to-dos as bullets. The model's prompt is rewritten with new examples and no longer sees the text before the cursor,
  which it used to copy into its answer; a light edit that drops the speaker's words or a meant repeat ("had had")
  falls back to the rules text. Rules alone: 171 → 207 of 222 evaluation cases; with Qwen3.5-2B: 175 → 208.
- Dictation audio is deleted after 14 days, as PRIVACY.md says; the text stays, and audio that is the only record of
  an untranscribed dictation stays for "Retry transcript".
- "Retry transcript" on a long meeting streams the recording from disk 30 s at a time instead of loading every
  track whole.

# Privacy

Super Flow runs every stage on your Mac: speech recognition, voice activity detection, text cleanup, speaker
diarization and meeting notes. Audio, transcripts, notes and settings never leave the Mac. There is no account, no
telemetry, no crash reporting and no analytics of any kind.

## What is stored, and where

Everything lives under `~/Library/Application Support/Super Flow/` with your normal file permissions (FileVault is the
at-rest encryption; the app adds none).

| Data | Where | Kept |
|---|---|---|
| Dictation history: raw transcript, cleaned text, what you edited it into, the app it went to, language, duration | `store.sqlite` | By the local data policy (Settings › Data and Privacy): kept, deleted after 24 h, or never stored |
| Dictation audio | `Audio/Dictations/<id>.caf` (`<id>.pcm` and `<id>.json` while recording, so a crash keeps it) | 14 days, for retry and playback, then deleted at the next launch (the dictation's text stays); audio of a dictation that was never transcribed stays until you retry or delete it, since it is the only record of what you said; not written when the policy is "never store" |
| Dictionary, replacement rules, learned words, snippets, transforms, styles | `store.sqlite` | Until you delete them |
| Notes (the Notes page) | `store.sqlite` (pre-1.0 builds kept `notes.json`; it is imported once and parked in `Backup/`) | Until you delete them |
| Meetings: title, participants from the calendar event, transcript with speaker labels, markers, your notes, summary, action items | `store.sqlite` | By the transcript retention (Settings › Data and Privacy; forever by default) |
| Meeting audio, one file per track (you / them) | `Audio/Meetings/<id>/` | 30 days by default, then deleted; transcripts and notes stay |
| Speaker names you assign | `store.sqlite`, inside the meeting | With the meeting |
| Downloaded models | `Models/<kind>/` | Until you delete them in Settings › Models |
| A damaged database, and the imported `notes.json` | `Backup/` | Until you delete them |
| Settings | `~/Library/Preferences/com.udsy.superflow.plist` | Until reset |

Settings › Data and Privacy offers "Delete all history", the retention choices and the local data policy. The hub's
History, Notes and Meetings pages delete single items.

### What is read, never stored

- Up to 500 characters around the cursor in the field you dictate into (for spelling and continuation), the frontmost
  app's bundle identifier, its window title and, in a browser, the page URL to pick the writing style. Off with
  "Context awareness". Password fields are never read and never dictated into.
- Which apps hold the microphone and the titles of their windows, to detect a meeting. Off with Settings › Notetaker ›
  Meeting detection.
- Calendar events for the current hour, to name a meeting (read-only, only with Calendar access).
- macOS's own "Press 🌐 key to" setting, to warn once when it collides with Fn shortcuts.
- The clipboard, for one paste: your previous clipboard is put back afterwards. Nothing is kept.

## The only network connections

| Purpose | Host | When |
|---|---|---|
| Model downloads | `https://huggingface.co` (the repositories listed in `THIRD_PARTY_NOTICES.md`; the bytes are served after a redirect by `https://cdn-lfs.huggingface.co` and `https://cas-bridge.xethub.hf.co`) | Automatically in the background after install, and when you choose a model in Settings › Models. Only on unmetered, unconstrained networks; paused in Low Power Mode and while you dictate or record; skipped when less than 10 GB is free. "Download models automatically" in Settings › Models turns it off. An optional mirror URL replaces the host. The Silero VAD ships inside the app and never downloads. |
| Update checks | `https://api.github.com/repos/udsy19/super-flow/releases/latest` and `https://github.com/udsy19/super-flow/releases/download/…` | A minute after launch and every six hours while "Install updates automatically" is on. The request is anonymous: no cookies, no identifiers. |

Nothing is sent in either case except the ordinary HTTP request for the file. Turn both off and the app makes no
connection at all.

On macOS 26, choosing "Apple on-device" as the dictation engine lets macOS download its own speech model for your
language the first time, through Apple's asset system; Super Flow sends nothing itself, and the audio never leaves the
Mac.

## Permissions

| Permission | Used for |
|---|---|
| Microphone | Listening only while you dictate or record a meeting. |
| Accessibility | Putting text into the field you are typing in, reading a little text around the cursor (off with "Context awareness"), noticing meeting apps. |
| Input Monitoring | Seeing the Fn key and shortcuts when Accessibility is not granted. |
| System Audio Recording (macOS 14.4+) or Screen Recording (earlier) | Capturing the other participants of a meeting, only while the Notetaker records. |
| Calendars (optional) | Meeting titles, attendees and reminders. Read-only. |

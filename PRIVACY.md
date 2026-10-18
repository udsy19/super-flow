# Privacy

Super Flow runs every stage on your Mac: speech recognition, voice activity detection, text cleanup, speaker
diarization and meeting notes. Audio, transcripts, notes and settings never leave the Mac. There is no account, no
telemetry and no crash reporting.

## What stays on this Mac

- `~/Library/Application Support/Super Flow/store.sqlite`: dictation history, dictionary, snippets, meetings,
  transcripts, summaries and action items.
- `~/Library/Application Support/Super Flow/Audio/`: dictation audio (kept 14 days for retry and playback) and
  meeting audio (kept 30 days by default, then deleted; transcripts and notes are kept until you delete them). Both
  retentions can be changed in Settings › Data and Privacy.
- `~/Library/Application Support/Super Flow/Models/`: the downloaded models.
- `~/Library/Preferences/com.udsy.superflow.plist`: settings.

Settings › Data and Privacy offers "Export history" (local JSON/CSV), "Delete all history" and the retention choices.
Speaker embeddings (used to recognise a named person across meetings) are stored locally and can be deleted per person.

## The only network connections

| Purpose | Host | When |
|---|---|---|
| Model downloads | `https://huggingface.co` (model files from the repositories listed in `THIRD_PARTY_NOTICES.md`; `https://cdn-lfs.huggingface.co` and `https://cas-bridge.xethub.hf.co` serve the bytes after a redirect) | Automatically in the background after install, and when you choose a model in Settings › Models. Only on unmetered, unconstrained networks; paused in Low Power Mode and while you dictate or record; skipped when less than 10 GB is free. "Download models automatically" in Settings › Models turns it off. An optional mirror URL replaces the host. |
| Update checks | `https://api.github.com/repos/udsy19/super-flow/releases/latest` and `https://github.com/udsy19/super-flow/releases/download/…` | A minute after launch and every six hours while "Install updates automatically" is on. The request is anonymous: no cookies, no identifiers. |

Nothing is sent in either case except the ordinary HTTP request for the file.

## Permissions

| Permission | Used for |
|---|---|
| Microphone | Listening only while you dictate or record a meeting. |
| Accessibility | Putting text into the field you are typing in, reading a little text around the cursor (off with "Context awareness"), noticing meeting apps. |
| System Audio Recording (macOS 14.4+) or Screen Recording (earlier) | Capturing the other participants of a meeting, only while the Notetaker records. |
| Calendars (optional) | Meeting titles, attendees and reminders. Read-only. |

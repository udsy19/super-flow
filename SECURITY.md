# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/udsy19/super-flow/security/advisories/new) for this repository.
You'll get a response within a few days, a fix is released as soon as practical, and you'll be credited in the
advisory if you want to be.

Only the latest release receives security fixes; running copies update themselves (see Updates below).

## What Super Flow is

A dictation and meeting-notes app that runs entirely on your Mac: no accounts, no analytics, no servers operated by
the project. It hears what you say and reads a little of what you type, which makes the microphone, the text around
the cursor and the stored transcripts the sensitive assets. The design keeps everything local and limits what the
app can reach.

## Threat model

### Capture

- The microphone is opened only while a shortcut is held or a meeting is being recorded, and released as soon as it
  ends. Dictated words are muted out of a meeting recording that runs at the same time.
- Password fields are never dictated into and never read: the focused element's secure role, and Secure Keyboard
  Entry held by the frontmost app, both refuse the dictation with a card.
- Context awareness reads at most 500 characters around the cursor, only with Accessibility granted and the setting
  on; it is passed to the local model and never stored.
- A meeting is never recorded without a click on "Record"; the detector only reads which apps hold the microphone
  and their window titles.

### Stored data

- Transcripts, notes and audio live in `~/Library/Application Support/Super Flow` with the user's file permissions.
  There is no additional at-rest encryption beyond FileVault; anyone with the user's files has the history. Retention
  settings and "Delete all history" are in Settings › Data and Privacy.
- The Flow Bar can be hidden from screen sharing and recordings (Settings › Notetaker).

### Insertion

- Text is inserted with a synthetic ⌘V through Accessibility, after which the previous clipboard is put back. Super
  Flow posts only that key, Return/Tab when you ask for them by voice, and ⌘C for a transform's selection fallback.
  It never reads the screen and never logs keystrokes: the event tap matches shortcut chords and lets everything
  else through.

### Models

- Models are fetched from Hugging Face over HTTPS and verified before use: single files by a pinned SHA-256, Core ML
  sets by a pinned repository commit and per-file hash. A file that fails verification is deleted. Downloads refuse
  expensive and constrained networks. The Silero VAD ships inside the app.
- Prompts treat dictated text and transcripts as data: the cleanup prompt tells the model never to follow
  instructions in the transcript, few-shot examples show an injection being cleaned rather than obeyed, and the
  guardrails drop outputs that answer, explain or add content. Meeting notes are checked against the transcript;
  anything the transcript cannot support is dropped.

### Updates (on by default)

- One anonymous HTTPS request to the GitHub API for this repository's latest release, a minute after launch and
  then every six hours. A newer DMG is downloaded and installed only if its SHA-256 matches the one in the release
  notes, the app inside passes a strict code-signature check, satisfies the designated requirement of the running
  copy (same signing identity), and its bundle id and version are what the release advertises.
- The verified copy is swapped in on quit or when idle. Anything that fails is logged and retried later.
- **Note:** releases are signed with the project's own identity, not notarized by Apple. The one-line installer
  verifies the DMG with `hdiutil verify` but, like any `curl | bash`, trusts GitHub Pages and GitHub Releases over
  HTTPS; read `scripts/install.sh` first if that matters to you.

### URL scheme

- `superflow://` URLs open hub pages and start or stop hands-free dictation. They cannot read or change data.

## Areas where a report is especially valuable

The password-field and Secure Keyboard Entry checks, the pasteboard swap and restore, prompt-injection resistance of
the cleanup and notes prompts, model download verification, update verification and the swap, and the event tap.

<h1 align="center">Super Flow</h1>

<p align="center">
  <b>Voice dictation and a meeting Notetaker for macOS that run entirely on your Mac.</b><br>
  Hold <kbd>Fn</kbd> and talk into any app. Press <kbd>⌥M</kbd> to take notes in a call. Nothing leaves the machine.
</p>

<p align="center">
  <a href="https://github.com/udsy19/super-flow/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/udsy19/super-flow?label=release&color=0A7AFF"></a>
  <a href="https://github.com/udsy19/super-flow/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/udsy19/super-flow/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-52CC64"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white">
  <img alt="Local models" src="https://img.shields.io/badge/models-100%25%20on--device-111">
</p>

<p align="center">
  <a href="https://udsy19.github.io/super-flow/"><b>Website</b></a> ·
  <a href="https://github.com/udsy19/super-flow/releases/latest/download/SuperFlow.dmg"><b>Download DMG</b></a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a> ·
  <a href="PRIVACY.md">Privacy</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

Super Flow is an open-source rebuild of the "hold a key, speak, get clean text" workflow, with every stage on the Mac:
speech recognition (NVIDIA Parakeet on the Neural Engine, Whisper as the multilingual fallback), voice activity
detection (Silero), text cleanup (Qwen3.5 through llama.cpp, with deterministic rules around it), speaker labels and
meeting notes (Qwen3.5-4B). There is no account, no server, no telemetry. The models download once, in the background,
from Hugging Face; after that the app works offline.

## Install

```sh
curl -fsSL https://udsy19.github.io/super-flow/install.sh | bash
```

Or download [`SuperFlow.dmg`](https://github.com/udsy19/super-flow/releases/latest/download/SuperFlow.dmg), drag Super
Flow to Applications and open it. Requires macOS 14 Sonoma or later; Apple silicon gets the full stack, Intel runs
Whisper on the CPU.

**Open Anyway.** The app is signed with the project's own identity and not notarized, so the first launch says it
"cannot be opened". Click Done, open *System Settings › Privacy & Security*, scroll down and click **Open Anyway** next
to the Super Flow message. The installer clears the quarantine flag for you, so this only applies to a manual DMG
install. (Terminal alternative: `xattr -dr com.apple.quarantine "/Applications/Super Flow.app"`.)

Uninstall: `curl -fsSL https://udsy19.github.io/super-flow/install.sh | bash -s -- --uninstall`.

## Permissions, and why

Super Flow asks for each permission on its own screen, only when the feature needs it. All of them are used locally.

| Permission | What it is for |
|---|---|
| **Microphone** | Listening while you hold the shortcut or record a meeting. The mic is released the moment you let go. |
| **Accessibility** | Pasting the text into the field you are typing in (a synthetic ⌘V, your clipboard put back afterwards), reading up to 500 characters around the cursor for spelling and continuation (off with "Context awareness"), and noticing meeting apps. |
| **Input Monitoring** | Seeing the Fn key and your shortcuts. With Accessibility granted the shortcut keys are swallowed so the app under them never sees them; with Input Monitoring alone they still reach the app. |
| **System Audio Recording** (macOS 14.4+) or Screen Recording (earlier) | Capturing the other participants of a meeting, only while the Notetaker records. |
| **Calendars** (optional) | Meeting titles, attendees and a reminder before a call. Read-only. |

## Fn gestures

| Gesture | What happens |
|---|---|
| Hold **Fn** | Push-to-talk: speak, let go, the text appears where the cursor is. |
| **Fn + Space** or double-tap **Fn** | Hands-free: a locked session with live text above the Flow Bar; press Fn, Fn+Space or Finish to stop. |
| **Fn + Control** | Command Mode (Settings › Experimental): say what to do with the selected text ("make this formal", "translate to Spanish"). |
| Triple-tap **Fn** or **⌥M** | Start or stop the meeting Notetaker. |
| **Esc** | Cancel the dictation, or close the card above the bar. |
| **⌃⌘V** / **⌃⌘C** | Paste / copy the last transcript. |
| **⌥1**, **⌥2**, **⌥3** | Transforms on the selected text: Polish, then your two custom prompts. |

No Fn key? Settings › General offers ⌃Space for push-to-talk and ⌃⌥Space for hands-free, and every shortcut can be
re-recorded. If macOS has "Press 🌐 key to" set to *Start Dictation*, Super Flow points it out once, since Apple's
dictation would also pop up on a double press.

## Features

- **Dictation** into any app, with a 300 ms pre-roll and 150 ms post-roll so first and last syllables are never cut,
  streaming recognition while you speak, and a 20-minute session limit with a warning at 19.
- **Cleanup** that keeps your words: fillers, false starts and self-corrections removed, numbers and lists written out,
  per-app style (Casual for messaging, Formal for mail and documents), an "All lowercase" or "No AI formatting" format
  per app, and guardrails that fall back to the rules-only text whenever the model rewrites, answers or hallucinates.
  "Undo AI edit" in History brings the raw transcript back.
- **Dictionary**: names and spellings the engines must keep, replacement rules ("misspelling → spelling"), and
  auto-learn from your edits (watched for 30 s after a paste; off in Settings › System).
- **Snippets**: a spoken trigger expands to a longer text, after cleanup, verbatim.
- **Styles** per app category and a cleanup level from None to High; style detection matches what is already in the
  field.
- **Command Mode** (Fn+Control) and **Transforms** (⌥1–⌥3): rewrite selected text by voice or with a saved prompt;
  case changes and lists work even before the model is downloaded.
- **Notetaker**: a "Meeting detected — Record?" prompt when Zoom, Teams, Meet, Slack, Webex, Discord, WhatsApp or
  FaceTime hold your microphone (always a click, never automatic; "Don't ask for this app" remembered), two tracks
  (you and them), a live transcript, speaker split after the call, notes with decisions and action items, markers,
  Markdown export, and audio kept 30 days then deleted.
- **History, Notes and Meetings** in the hub window; the **Flow Bar** at the bottom of the screen shows every state,
  "Getting ready… N%" while a model downloads, and every failure as a plain card with the fix.
- **Updates**: a background check of GitHub Releases every six hours, verified by SHA-256 and code signature, swapped in
  on quit. Off in Settings.

## Models, sizes, downloads

Models download automatically after install, speech first, one at a time, only on unmetered networks, never in Low
Power Mode, never while you dictate, and never when less than 10 GB is free. "Download models automatically" in
Settings › Models turns it off; each model can also be downloaded, paused, deleted or imported from a file there.

Settings › Models also picks the **dictation engine** on Apple silicon:

- **Parakeet (multilingual, default)**: the most accurate, 25 European languages.
- **Nemotron (English, fastest, live text)**: shows your words while you speak and has the text ready about 20 ms
  after you let go of the key (Parakeet: about 60 ms). English only: other languages and meetings keep using
  Parakeet. Downloads 627 MB when you choose it.
- **Apple on-device (macOS 26)**: nothing to download; macOS's own speech model, 10 languages, one at a time.

Macs with 24 GB or more can also switch the **cleanup model** from Qwen3.5 2B to Qwen3.5 4B ("best quality": a few
points more accurate, about twice as slow), which they already have for meeting notes.

| Model | Used for | Size | Licence |
|---|---|---|---|
| Parakeet TDT 0.6B v3 (Core ML, Apple silicon) | Dictation in 25 European languages | 470 MB | CC-BY-4.0 |
| Nemotron Speech Streaming EN 0.6B, 1120 ms (Core ML, Apple silicon) | Live English dictation, when chosen | 627 MB | NVIDIA Open Model License |
| Apple SpeechTranscriber (macOS 26) | Dictation, when chosen | — (part of macOS) | Apple |
| Whisper base (q5_1) | Bootstrap and Intel dictation, 99 languages | 60 MB | MIT |
| Whisper large-v3-turbo (q5_0) | Multilingual fallback, on demand | 574 MB | MIT |
| Whisper small (q5_1) | Intel Macs with 16 GB+ | 190 MB | MIT |
| Silero VAD v6.2 | Voice activity detection — bundled, nothing to download | 0.9 MB | MIT |
| Qwen3.5-2B (Q4_K_M) | Cleanup (the default from 16 GB), Transforms, Command Mode; meeting notes on 8 GB Macs | 1.28 GB | Apache-2.0 |
| Qwen3.5-0.8B (Q4_K_M) | Meeting notes on Intel Macs | 533 MB | Apache-2.0 |
| Qwen3.5-4B (Q4_K_M) | Meeting notes; cleanup when chosen on 24 GB Macs | 2.74 GB | Apache-2.0 |
| Speaker diarization (Community-1, Core ML) | Who said what in meetings | 22 MB | CC-BY-4.0 |
| LocalVQE 1.3 (Core ML) | Echo removal in meetings | 20 MB | Apache-2.0 |

A 16 GB Apple silicon Mac installs about 1.8 GB for dictation and 2.8 GB more for meetings; an 8 GB one about 0.5 GB
and 1.3 GB. 8 GB and Intel Macs clean dictation with the rules alone, which scored higher there than the 0.8B model
([cleanup-models.md](docs/specs/cleanup-models.md) §5); choosing Qwen3.5 2B in Settings › Models › Cleanup model turns
on LLM cleanup, Transforms and Command Mode. Everything lives in `~/Library/Application Support/Super Flow/Models`. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attributions and [PRIVACY.md](PRIVACY.md) for the exact hosts.

## Building

Command Line Tools only; no Xcode project.

```sh
git clone https://github.com/udsy19/super-flow.git && cd super-flow
swift build                       # every module, warning-free
swift run SuperFlowSelfTest       # headless checks; real-model cases run with SUPERFLOW_DEV_MODELS=<folder>:<folder>
                                  # (the cleanup evaluation set scores itself; SUPERFLOW_EVAL_VERBOSE=1 lists failures)
./scripts/signing-setup.sh        # once: a project-local signing identity, so privacy grants survive rebuilds
./scripts/build-app.sh            # build/Super Flow.app (UNIVERSAL=1 for Apple silicon + Intel)
```

`build-app.sh` embeds the whisper.cpp and llama.cpp frameworks, the cue sounds and the bundled VAD, signs the bundle
and then runs static launch checks (entitlements, rpaths, every `@rpath` dependency present, resources); it never
launches the app. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains the modules, the contracts and the pipeline;
[CONTRIBUTING.md](CONTRIBUTING.md) the conventions.

## Licence and credits

Super Flow is MIT-licensed (see [LICENSE](LICENSE)). It stands on
[FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0: Parakeet, VAD, diarization and LocalVQE on
Core ML), [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and [llama.cpp](https://github.com/ggml-org/llama.cpp)
(MIT), the NVIDIA Parakeet and Nemotron, OpenAI Whisper, Silero, Qwen, pyannote and WeSpeaker models, and the SQLite
that ships with macOS. Every component and model licence is listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Nemotron Speech Streaming EN 0.6B is licensed by NVIDIA Corporation under the NVIDIA Open Model License; the agreement
ships in the app at `Contents/Resources/Licenses/NVIDIA-Open-Model-License.txt` and in this repository under
[Resources/Licenses](Resources/Licenses/NVIDIA-Open-Model-License.txt).

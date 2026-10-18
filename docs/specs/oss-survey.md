# Open-source survey — dictation, meeting notes and on-device speech on macOS

What already exists on GitHub that the rebuild can depend on, learn from, or must stay away from. It covers dictation apps, speech engines, local LLM runtimes, meeting notetakers, system-audio capture and meeting detection. Companion to `behaviour.md` (what to build), `local-models.md` (model choice and budgets) and `ui-reference.md` (look).

## 0. Method, legend and licence policy

- Data was pulled on **2026-10-18** with the GitHub CLI: `gh search repos`, `gh repo view --json …`, `gh api repos/<o>/<r>/readme|license|contents|git/trees`, `gh release view`. Model licences were read from the Hugging Face model API (`cardData.license`).
- Nothing was cloned or run. READMEs and source files were read as data.
- Star counts and last-push dates are a snapshot. "Last push" is the repo's `pushedAt`.
- **[V]** = verified from GitHub or Hugging Face data in this survey.
- **[U]** = from memory or vendor docs, not re-verified here. Check before relying on it.

**Licence policy for our MIT repository**

| Licence | What we may do |
|---|---|
| MIT, Apache-2.0, BSD, ISC | Depend on it, or reuse code with attribution. Keep the licence/NOTICE file in the app bundle. |
| MPL-2.0 | Depend on it unmodified. Do not copy files into our tree. |
| GPL-2/3, AGPL-3, LGPL linked statically | **Study only.** Never copy code, structure or prompts verbatim, and never link it. |
| No licence, or a commercial/"source-available" licence | All rights reserved. **Do not use.** Reading the README for ideas is fine. |
| Model weights | Licensed separately from the code (CC-BY-4.0, NVIDIA Open Model License, Llama/Gemma terms…). See §7. |

---

## 1. Dictation apps (Wispr-Flow-like)

| Name | Repo | Licence | Stars | Last push | Lang | What it does | Adopt? |
|---|---|---|---|---|---|---|---|
| Handy | `cjpais/Handy` | MIT | 34,088 | 2026-10-15 | Rust (Tauri) | Cross-platform offline dictation. Hold-to-talk or tap-to-toggle; Silero VAD; Whisper or Parakeet; paste with clipboard restore; history; dictionary; post-processing toggle; CLI flags. | **Learn** paste reliability ("Reliable Paste": delay the clipboard restore until the target app has read it; configurable before/after delays), and the Fn caveat (Fn works only on Apple keyboards). |
| OpenWhispr | `OpenWhispr/openwhispr` | MIT | 9,555 | 2026-10-18 | JS (Electron) | Dictation + meetings + notes + agent. whisper.cpp and sherpa-onnx; meeting auto-detect (Zoom/Teams/FaceTime); live diarization; calendar; translation hotkey. | **Learn** the feature set. Electron, so no code reuse. It notes that ONNX Runtime stopped shipping macOS x86_64 builds in 1.24, so diarization is unavailable on Intel [V README]. |
| VoiceInk | `Beingpax/VoiceInk` | **GPL-3.0** | 6,853 | 2026-10-18 | Swift | Native dictation. whisper.cpp + FluidAudio Parakeet + transcribe.cpp; per-app "Modes" (prompt per app/URL); context awareness; personal dictionary with auto-learn and word replacements; history; MediaRemote pause. | **Study only.** It confirms the module split we plan: Enhancement, Dictionary/AutoLearn, Modes, Paste (`CursorPaster`, `ClipboardManager`, `PasteMethod`). |
| FluidVoice | `altic-dev/FluidVoice` | **GPL-3.0** | 12,275 | 2026-10-17 | Swift | Dictation on FluidAudio Parakeet/Nemotron/Apple Speech/Whisper. Per-app prompt sets; insertion through Accessibility; meeting auto-detect signals. Its "Fluid Intelligence" cleanup model is closed. | **Study only.** |
| Hex (Swift, archived) | `kitlangton/Hex` | MIT | 2,902 | 2026-10-14 (archived) | Swift (TCA) | Press-and-hold or double-tap lock; FluidAudio Parakeet + WhisperKit; clipboard paste via CGEvent with restore. Moved to a Rust rewrite (`anomalyco/hex`, MIT, 381★). | **Borrow pattern**: `HotKeyProcessor` state machine (idle → pressAndHold → doubleTapLock; double-tap threshold 0.3 s; Esc cancels) with unit tests [V source]. |
| BetterWispr | `opennookorg/betterwispr` | Apache-2.0 | 393 | 2026-10-15 | Swift (SwiftPM) | Dictation + **meetings**. Built with plain `swift build` plus a bundle script. Deps: `argmax-oss-swift` 1.1.0, FluidAudio 0.17.5, `mattt/llama.swift` 2.10549.0, Sparkle. Has a meeting detector, a Core Audio system tap, speaker detection, voice commands ("comma", "new line", "scratch that"), learned corrections, MCP (read-only). | **Closest architectural twin.** Apache-2.0, so patterns and snippets may be reused with attribution. Proves the SwiftPM-only build with this dependency set [V Package.swift, build-app.sh]. |
| Muesli | `Muesli-HQ/muesli` | MIT | 1,431 | 2026-10-15 | Swift | Dictation (Parakeet TDT ≈ 0.13 s) + Granola-style meetings: process tap with ScreenCaptureKit fallback; Silero-VAD chunk rotation; FluidAudio diarization; camera+mic meeting detection; calendar "Join & Transcribe"; templates; Ask Meetings; Markdown/PDF export; Jaro-Winkler dictionary; App Intents. Building it needs Xcode 26.6. | **Borrow patterns** (MIT): `MeetingCandidateResolver`, `MeetingAutoStopPolicy`, `BrowserMeetingActivityCollector`, `DictationPasteSpacing`, `FloatingMeetingTranscriptPanel`, VAD chunk rotation. |
| Dictate Anywhere | `hoomanaskari/mac-dictate-anywhere` | MIT | 35 | 2026-10-16 | Swift | Fn-key dictation on FluidAudio Parakeet. AX reads on a serial worker with messaging timeouts (300–500 ms); list insertion; CJK insertion tests. | **Borrow** the AX timeout discipline. |
| MiniWhisper | `andyhtran/MiniWhisper` | MIT | 34 | 2026-08-16 | Swift | Minimal menu-bar dictation on Parakeet. | Reference only. |
| Whispree | `Arsture/whispree` | MIT | 129 | 2026-08-23 | Swift | Dictation tuned for prompts: screenshot context, "Structured" mode, Quick-Fix dictionary hotkey, iCloud Drive dictionary sync. | Idea: a **quick "add misheard word" hotkey**. |
| SpeakoFlow | `AbhishekBarali/SpeakoFlow` | MIT | 335 | 2026-10-18 | Rust (Tauri) | Dictation + meetings beta; Parakeet / Nemotron / Whisper; dictionary + learned corrections (Windows). | Reference only. |
| Buzz | `chidiwilliams/buzz` | MIT | 22,063 | 2026-10-17 | Python | File transcription and translation (Whisper family). | Not a dictation app. Reference for file import UX. |
| Whispering / Epicenter | `EpicenterHQ/epicenter` | **AGPL-3.0-or-later** | 4,823 | 2026-10-18 | TS | Local-first app suite including Whispering dictation. | **Study only.** |
| VoiceTypr | `ideaplexa/voicetypr` | **AGPL-3.0** | 737 | 2026-10-16 | Rust | Dictation on Parakeet. | **Study only.** |
| SayIt | `crosswk/SayIt` | **AGPL-3.0** | 443 | 2026-10-09 | TS | Windows dictation. | No. |
| TypeWhisper | `TypeWhisper/typewhisper-mac` | **GPL-3.0** | 1,864 | 2026-10-18 | Swift | Local STT with meeting audio activity collector. | **Study only.** |
| whisper-writer / nerd-dictation | `savbell/whisper-writer`, `ideasman42/nerd-dictation` | **GPL-3.0** | 1,105 / 1,935 | 2024-08 / 2025-10 | Python | Older hotkey dictation. | No. |
| voxtype / hyprwhspr | `peteonrails/voxtype`, `goodroot/hyprwhspr` | MIT | 1,666 / 1,249 | 2026-10 | Rust / Python | Linux push-to-talk dictation. | Not macOS. Ignore. |

**What the mature apps agree on** [V from the READMEs and sources above]:

1. **Hotkeys.** Hold-to-talk plus double-tap (or a toggle) for hands-free. Fn is usable only on Apple keyboards, so offer a modifier chord as well. A tested pure state machine handles the logic (Hex).
2. **Insertion.** Write the clipboard, send ⌘V with CGEvent, then restore the clipboard. Restore only after the target app has read the pasteboard (Handy "Reliable Paste"; Wispr Flow does the same with a lazy data provider). Typing with AX `kAXSelectedText` is a fallback for apps where paste is unreliable. If paste cannot reach the app, leave the text on the clipboard (BetterWispr).
3. **Cleanup.** An optional LLM pass with per-app prompts ("Modes" / "Per-App Configuration"). Filler removal and voice commands are deterministic rules.
4. **Dictionary.** Recognition hints, replacement pairs and auto-learn from user corrections. Fuzzy match with Jaro-Winkler (Muesli). Parakeet supports CTC vocabulary boosting.
5. **Models.** Download in-app with a model library. Parakeet TDT v3 is the default on Apple silicon; Whisper turbo covers 99 languages; Apple Speech is an option on macOS 26.

---

## 2. Speech engines and libraries

| Name | Repo | Licence | Stars | Last push / release | Lang | Notes | Adopt? |
|---|---|---|---|---|---|---|---|
| **FluidAudio** | `FluidInference/FluidAudio` | Apache-2.0 | 3,129 | 2026-10-16 / v0.17.7 (2026-10-08) | Swift | Core ML models on the **Neural Engine**. Covers: Parakeet TDT v2/v3 batch ASR (25 European languages + Japanese); Parakeet EOU 120M and Nemotron streaming 0.6B; Silero VAD; offline diarization (pyannote Community-1 segmentation + WeSpeaker + VBx); streaming diarization (LS-EEND, Sortformer ≤ 4 speakers, pyannote 3.1); speaker embeddings; LocalVQE echo cancellation (mic + far-end reference, 16 ms latency, beta); CTC vocabulary boosting. SwiftPM, swift-tools 6.0, **macOS 14+**. With Swift 6.2+ the `TTS`, `Diarizer` and `NemoTextProcessing` traits can be switched off. Has one binary target (`NemoTextProcessing.xcframework`, checksum-pinned). Models are fetched from Hugging Face as compiled `.mlmodelc`. | **Depend.** It is the de-facto engine of this ecosystem: about 40 shipping apps are listed in its README [V]. |
| whisper.cpp | `ggml-org/whisper.cpp` | MIT | 54,469 | v1.9.5 (2026-10-06) | C/C++ | Whisper on ggml with Metal + optional Core ML encoder. Nightly tag `b5454` (paired with v1.9.5) ships `whisper-b5454-xcframework.zip` (65.8 MB). Its macOS slice is **arm64 + x86_64**, built with `GGML_METAL_EMBED_LIBRARY=ON` and `WHISPER_COREML=ON` (fallback allowed), deployment target 13.3 [V build-xcframework.sh]. | **Depend** (binaryTarget) for 99-language dictation and the **Intel fallback**. |
| WhisperKit / SpeakerKit (argmax-oss-swift) | `argmaxinc/argmax-oss-swift` | MIT | 6,406 | v1.1.1 (2026-10-08) | Swift | Whisper in Core ML, pyannote diarization (SpeakerKit) and TTS. macOS 14+. Some features sit in the paid "Pro SDK". | Optional. It overlaps with FluidAudio plus whisper.cpp, so we skip it unless we need Whisper on the ANE. |
| transcribe.cpp | `handy-computer/transcribe.cpp` | MIT | 2,067 | v0.4.0 (2026-10-12) | C++ | One ggml runtime for 16+ STT families (Whisper, Parakeet TDT/EOU GGUF, Moonshine streaming, Nemotron streaming, Qwen3-ASR, Canary, SenseVoice…), plus Sortformer diarization, Silero VAD and language ID. Ships `TranscribeCpp.xcframework.zip` and a macOS x86_64 CPU build. Swift binding: `Beingpax/Transcribe-cpp-swift` (MIT). | **Watch.** Young (0.x) but promising as a single engine that also covers Intel. Re-evaluate at 1.0. |
| sherpa-onnx | `k2-fsa/sherpa-onnx` | Apache-2.0 | 15,355 | v1.13.8 (2026-09-10) | C++ | ASR (streaming + offline), VAD, diarization, TTS on ONNX Runtime. Ships macOS static and shared libs (arm64, x86_64, universal2) but **no xcframework**. | Fallback only. Large binaries, and ONNX Runtime has dropped macOS x86_64 in newer versions (see OpenWhispr). |
| Moonshine | `moonshine-ai/moonshine` | MIT for code and English + streaming models. Legacy non-English base/tiny models use a **non-commercial** Moonshine Community License [V LICENSE]. | 11,253 | 2026-10-02 | C++ | Very low-latency streaming STT. Libraries for iOS/macOS. | Optional streaming preview engine. Avoid the non-commercial models. |
| parakeet-mlx / mlx-audio | `senstella/parakeet-mlx` (Apache-2.0, 987★), `Blaizzy/mlx-audio` (MIT, 8,060★) | — | — | 2026-10 | Python | MLX implementations. | Not Swift. Benchmark reference only. |
| SwiftWhisper / whisper.spm | `exPHAT/SwiftWhisper`, `ggerganov/whisper.spm` | MIT | 784 / 191 | 2024-05 | Swift/C | Old SwiftPM wrappers of whisper.cpp. | No: stale. Use the official xcframework. |
| Silero VAD | `snakers4/silero-vad` | MIT | 10,461 | 2026-09-29 | Python/ONNX | The standard VAD. Ships inside FluidAudio as Core ML [V model card: MIT]. | Via FluidAudio. |
| pyannote-audio | `pyannote/pyannote-audio` | MIT (code) | 10,671 | 2026-10-18 | Python | Diarization research toolkit. The Community-1 pipeline weights are **CC-BY-4.0** and gated ("auto") on Hugging Face [V]. | Via FluidAudio's Core ML conversion, with attribution. |
| faster-whisper, openai/whisper, NeMo | `SYSTRAN/faster-whisper` (MIT), `openai/whisper` (MIT), `NVIDIA-NeMo/Speech` (Apache-2.0) | — | — | — | Python | Training and reference implementations. | Reference only. |
| **Apple SpeechAnalyzer / SpeechTranscriber** | (system, macOS 26) | Apple SDK | — | — | Swift | On-device long-form and streaming transcription with system-managed assets (`AssetInventory`) and a dictation-style transcriber. No model download or app-bundled weights [U Apple docs]. | **Optional engine on macOS 26** (zero download). Muesli and FluidVoice already offer it [V]. |

---

## 3. Local LLM runtimes (cleanup, transforms, summaries)

| Name | Repo | Licence | Stars | Release | Notes | Adopt? |
|---|---|---|---|---|---|---|
| llama.cpp | `ggml-org/llama.cpp` | MIT | 131,617 | build tags `bNNNNN` (latest `b11721`, 2026-10-18); semver tags (v0.7.0) carry no binaries | Every build tag ships `llama-bNNNNN-xcframework.zip` (66.8 MB, Metal embedded, macOS 13.3+) [V]. | **Depend**, through a binaryTarget. |
| llama.swift | `mattt/llama.swift` | MIT | 83 | 2.10549.0 (wraps `b10549`) | Thin SwiftPM package: `binaryTarget(url: …/b10549/llama-b10549-xcframework.zip, checksum: 6367…bff4)` plus a `LlamaSwift` target. macOS 13+. Used by BetterWispr [V]. | **Depend** (pinned `exact:`), or copy its five-line pattern into our own binaryTarget to pick newer builds. |
| LLM.swift | `eastriverlee/LLM.swift` | MIT | 882 | 2026-07-19 | Convenience layer over llama.cpp. | No. It adds little over llama.swift. |
| mlx-swift / mlx-swift-lm | `ml-explore/mlx-swift` (MIT, 2,064★), `ml-explore/mlx-swift-lm` (MIT, 837★, 3.32.3) | MIT | — | — | Fast on Apple silicon. However **"SwiftPM (command line) cannot build the Metal shaders"**: the build needs `xcodebuild` or CMake [V mlx-swift README]. | **Avoid**: it breaks our Command-Line-Tools-only build. |
| Apple Foundation Models | (system, macOS 26) | Apple SDK | — | — | On-device ~3B model with guided generation (`@Generable`). Available only when Apple Intelligence is on and on Apple silicon. Context window about 4K tokens, so long meetings need map-reduce [U Apple docs; Nutola map-reduces for this reason, V]. | **Optional engine on macOS 26** for cleanup and short summaries. |
| Ollama / LM Studio | — | — | — | — | External local servers that many notetakers use (Meetily, anarlog, Muesli, OpenOats). | Optional "use my local server" endpoint later. Never required. |

---

## 4. Meeting notetakers

| Name | Repo | Licence | Stars | Last push | Lang | What it does | Adopt? |
|---|---|---|---|---|---|---|---|
| Meetily | `Zackriya-Solutions/meetily` | MIT | 31,902 | 2026-09-15 | Rust (Tauri + Next.js) | Live transcription (Whisper/Parakeet), speaker diarization, summaries through local Ollama or BYO endpoints, mic + system audio "with intelligent ducking and clipping prevention", audio import and re-transcribe. Has a paid "PRO" tier. | **Learn**: the mixing and ducking of the two sources, and re-transcribe with another model. |
| anarlog (ex-Hyprnote) | `fastrepl/anarlog` | MIT (community app; `enterprise/` is commercial) | 9,526 | 2026-10-18 | Rust (Tauri v2) | "Open source Granola alternative": no bot joins the call, local SQLite plus plain files, Markdown export, local STT, summaries/chat from any provider, calendar plugin, crates for capture/STT/diarization. | **Learn** the data model: sessions + notes + transcript, the user's own notes merged with an AI summary, Markdown export. Do not read `enterprise/`. |
| Muesli | `Muesli-HQ/muesli` | MIT | 1,431 | 2026-10-15 | Swift | See §1. Meetings: process tap by default with SCK fallback; mic = "You", system = "Others"; VAD chunk rotation; diarization; templates; Ask Meetings with citations; auto-stop policy; calendar join links; post-meeting hooks. | **Borrow patterns** (MIT). |
| BetterWispr | `opennookorg/betterwispr` | Apache-2.0 | 393 | 2026-10-15 | Swift | See §1. Meetings: `MicrophoneActivity` (per-process input via Core Audio process objects), `MeetingDetection` (bundle-id table + AX browser window titles with a 0.25 s messaging timeout), `SystemAudioTap` (global stereo tap that excludes its own process, private aggregate device with drift compensation), 30 s prompt, summaries through a local LLM. | **Borrow patterns** (Apache-2.0). |
| Meeting Transcriber | `pasrom/meeting-transcriber` | MIT | 207 | 2026-10-18 | Swift | Auto-records Teams/Zoom/Webex by polling window titles. Browser meetings are opt-in behind a consent prompt; mic-input detection is opt-in per app. Records app audio + mic at 16 kHz per track, transcribes with WhisperKit/Parakeet, diarizes each track separately with FluidAudio, recognises speakers across meetings (cosine similarity of embeddings), and handles echo bleed (detect, then optional AEC or dedup). Produces a Markdown protocol: Summary · Decisions · Tasks · Transcript. | **Borrow**: dual-track diarization, cross-meeting speaker recognition and echo-bleed handling. |
| Nutola | `Nutola/Nutola` | MIT | 3 | 2026-08-19 | Swift | Mic-usage meeting detection; mic via AVAudioEngine + others via process tap; FluidAudio diarization (≈ 22 MB); calendar attendees as rename suggestions; Foundation Models summaries with **map-reduce**; live draft notes; editable templates; per-meeting folders of JSON + Markdown + m4a. | **Borrow**: map-reduce summaries, attendee-based speaker naming, plain-file export. |
| OpenOats | `yazinsai/OpenOats` | MIT | 2,609 | 2026-10-13 | Swift | Records both sides locally; live suggestions from a knowledge folder; asks for a recording-consent acknowledgement before the first session; Parakeet/Whisper/Qwen3-ASR. Building it needs Xcode 26. | **Borrow** the first-run consent acknowledgement. |
| minutes | `silverstein/minutes` | MIT | 1,557 | 2026-10-18 | Rust | Local meeting notes exposed to MCP clients; Swift mic check. | Reference only. |
| StenoAI | `stenolabs/stenoai` | MIT | 1,340 | 2026-10-17 | Python | Privacy-first notetaker; Swift mic monitor. | Reference only. |
| Amurex | `thepersonalaicompany/amurex` | **AGPL-3.0** | 2,864 | 2025-05-27 | JS | Meeting assistant. | **Study only**. Stale. |
| Screenpipe | `screenpipe/screenpipe` | **Commercial licence** (source-available) | 21,976 | 2026-10-18 | Rust | Continuous screen and audio recording. | **Do not use.** |
| Omi desktop | `BasedHardware/omi` | MIT | 13,764 | 2026-10-18 | Python/Swift | Has `ConferencingApps.swift` and a call-audio probe. | Reference for the list of conferencing bundle ids. |

**What a best-in-class local notetaker does** (consensus of the projects above) [V]:

1. **No bot.** Capture on the device: mic through AVAudioEngine and other participants through a Core Audio process tap.
2. **Two tracks.** Mic = "You", system = "Others". Diarize only the system track, or each track separately, so speaker labels are cleaner and echo is avoided.
3. **VAD-segmented, chunked ASR during the meeting.** The final transcript is ready seconds after stop. An optional streaming model gives a live preview.
4. **Diarization.** Offline pyannote-style after the meeting for accuracy; Sortformer or LS-EEND live. Speaker names come from calendar attendees, and voice embeddings are remembered across meetings.
5. **Templated summary.** Summary, decisions, action items and follow-ups, produced with **map-reduce** for long meetings. The user can re-summarise with another template.
6. **Library.** Folders, search, "ask across meetings" with citations, and export to Markdown/PDF/clipboard.
7. **Consent.** A one-time acknowledgement, an optional chat notice, and explicit prompts for browser meetings.

---

## 5. System-audio capture on macOS

| Approach | OS | Permission | Pros | Cons | OSS reference |
|---|---|---|---|---|---|
| **Core Audio process tap** (`CATapDescription` + `AudioHardwareCreateProcessTap` + private aggregate device with `kAudioAggregateDeviceTapListKey`, `kAudioSubTapDriftCompensationKey`, `TapAutoStart`) | 14.2+ (Muesli and meeting-transcriber require 14.2; AudioCap documents it as 14.4) | **"System Audio Recording Only"** (TCC audio capture), with prompt text from `NSAudioCaptureUsageDescription` (Wispr Flow ships this key). There is **no public API to preflight or request it**: AudioCap uses private TCC SPI behind a build flag, otherwise the prompt appears on first capture [V AudioCap]. A purple menu-bar dot appears while capturing. | Per-process or global (exclude our own PID); no Screen Recording permission; captures Bluetooth/AirPods output; low latency. | Sparse documentation; the device format is usually 48 kHz Float32 stereo, so resample to 16 kHz mono ourselves. | `insidegui/AudioCap` (BSD-2-Clause, 514★, sample code); `opennookorg/betterwispr` `SystemAudioTap.swift` (Apache-2.0); `makeusabrew/audiotee` (**no licence**: read only) |
| ScreenCaptureKit audio (`SCStreamConfiguration.capturesAudio`, `excludesCurrentProcessAudio`) | 13+ | **Screen Recording** (heavier prompt; on macOS 15+ it periodically asks again) | Stable public API. | Wrong permission story for a notetaker; requires a display/window filter. | Muesli (fallback path) |
| Virtual drivers (BlackHole, Loopback) | any | install a kernel/driver | — | Install friction; changes the user's output routing. | **Avoid.** |

Echo and bleed: when the user is on speakers, remote voices leak into the mic. Options: (a) diarize the tracks separately and **drop mic segments that duplicate system-track text** (meeting-transcriber's dedup, off by default because it can drop quiet remarks); (b) neural AEC using the system track as far-end reference (FluidAudio **LocalVQE**, beta); (c) recommend headphones in the UI. The rebuild uses (a) as an opt-in and (b) once LocalVQE is stable.

---

## 6. Meeting detection

| Signal | API | Notes | OSS reference |
|---|---|---|---|
| **Which process is using the mic** | `kAudioHardwarePropertyProcessObjectList` → per process `kAudioProcessPropertyIsRunningInput` + `kAudioProcessPropertyBundleID`, with listeners on both (macOS 14+) | Event-driven. Maps helper processes to their app (e.g. `com.apple.WebKit.GPU` → Safari). Must exclude our own process. | BetterWispr `MicrophoneActivity.swift` (Apache-2.0); found in Muesli, OpenOats, FluidVoice (GPL), TypeWhisper (GPL), minutes, StenoAI, Omi by code search [V] |
| Any app using the default input device | `kAudioDevicePropertyDeviceIsRunningSomewhere` on the input device | Older and coarse (no "who"). | OverSight (`objective-see/OverSight`, **GPL-3.0**: study only) |
| **Native call apps** | bundle-id table: `us.zoom.xos`, `com.microsoft.teams2` / `com.microsoft.teams`, `com.tinyspeck.slackmacgap` (huddles), `Cisco-Systems.Spark` / `com.webex.meetingmanager`, `com.apple.FaceTime` / `com.apple.avconferenced`, Discord, WhatsApp, Signal, Telegram | Mic-in-use + known app = meeting. | BetterWispr `MeetingDetection.swift` [V] |
| **Browser meetings** | AX window titles of the mic-using browser (e.g. "Meet - … - Google Chrome", "Microsoft Teams", "Zoom", "Huddle", "Whereby", "Jitsi Meet") with `AXUIElementSetMessagingTimeout(0.25)` | Needs Accessibility (already granted for dictation). Wispr Flow goes further and scans browser tab strips (`MeetingTabScanner`). | BetterWispr; Muesli `BrowserMeetingActivityCollector`; meeting-transcriber (opt-in, consent-gated) |
| Camera + mic together | AVCaptureDevice `isInUseByAnotherApplication` + mic signal | Cuts false positives (Muesli: "camera alone won't trigger"). | Muesli |
| Window-title polling for native apps | CGWindowList / AX titles | Teams/Zoom meeting windows have recognisable titles. | meeting-transcriber |
| **Calendar** | EventKit (`EKEventStore`, `EKEventStoreChangedNotification`); parse join URLs (Zoom, Meet, Teams, Webex, Chime, FaceTime) from location, notes and URL | Prefills title and attendees; offers "Join & Transcribe" / "Transcribe only"; shows a countdown in the menu bar. | Muesli, Nutola (MIT) |
| Meeting end | the mic-using process stops input + silence on both tracks for N minutes; calendar end time | Auto-stop policy with a check-in prompt. | Muesli `MeetingAutoStopPolicy`; Wispr Flow (auto-end, check-ins at calendar end / 1 h / max length) |

---

## 7. Model licences (verified on Hugging Face) [V]

| Model | Licence | Use |
|---|---|---|
| Parakeet TDT 0.6B v2 / v3 (NVIDIA; FluidAudio Core ML conversions) | CC-BY-4.0 | Dictation + meetings (attribution in About) |
| Parakeet Realtime EOU 120M, Nemotron Speech Streaming 0.6B (FluidAudio Core ML) | NVIDIA Open Model License | Live preview; commercial use allowed under its terms — keep the licence text |
| Sortformer streaming diarizer (FluidAudio Core ML) | CC-BY-4.0 on the HF card; FluidAudio README says NVIDIA Open Model License | Treat as NVIDIA Open Model License to be safe |
| pyannote speaker-diarization-community-1 | CC-BY-4.0 (gated "auto" upstream); FluidAudio repackage `speaker-diarization-coreml` is "scoped-cc-by-4.0" | Offline diarization (attribution) |
| Silero VAD (Core ML) | MIT | VAD |
| Whisper large-v3-turbo (and the whisper.cpp ggml weights, WhisperKit Core ML weights) | MIT | Multilingual / Intel |
| Qwen3 1.7B / 4B | Apache-2.0 | Cleanup, transforms, summaries |
| Qwen2.5 3B Instruct | Qwen Research licence (**non-commercial**) | Avoid |
| Llama 3.2 3B Instruct | Llama 3.2 Community licence (gated) | Avoid as the default |
| Gemma 3 4B it | Gemma terms (gated) | Optional |
| Phi-4-mini-instruct | MIT | Alternative small LLM |
| Moonshine (English + streaming) | MIT; legacy non-English base/tiny are non-commercial | Optional |

---

## 8. Recommendations

### 8.1 Dependencies (exactly these)

| # | Dependency | How | Pin | Why |
|---|---|---|---|---|
| 1 | **FluidAudio** (Apache-2.0) | SwiftPM package `.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7")`. With a Swift 6.2+ toolchain pass `traits: ["Diarizer"]` to drop TTS. | `0.17.7` | Parakeet TDT v3 dictation ASR (ANE), Parakeet EOU / Nemotron live captions, Silero VAD, offline + streaming diarization, speaker embeddings, CTC vocabulary boosting, LocalVQE. Core ML only, so **no Metal compiler is needed**: models arrive precompiled from Hugging Face. |
| 2 | **whisper.cpp** (MIT) | `.binaryTarget(name: "whisper", url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip", checksum: <swift package compute-checksum>)` — GitHub reports sha256 `e57f8c48…92393b` for the zip | `b5454` (= v1.9.5) | 99-language dictation and meetings (Whisper large-v3-turbo); universal macOS slice, so it is the **Intel fallback**. Metal is embedded, so no `metal` tool is needed. |
| 3 | **llama.cpp** (MIT) | Prefer our own `.binaryTarget(name: "llama", url: ".../b11721/llama-b11721-xcframework.zip", checksum: …)` (GitHub sha256 `9efc8f94…7460f`) plus a thin Swift wrapper in our tree. Alternative: depend on `mattt/llama.swift` `exact: "2.10549.0"`. | `b11721` (bump deliberately) | Cleanup LLM, Transforms, command mode, meeting summaries (Qwen3 GGUF). |
| 4 | Apple frameworks only | — | — | AVFoundation (mic), **Core Audio process taps** (system audio), ScreenCaptureKit (fallback), **EventKit** (calendar), ApplicationServices/AX (context, browser titles, paste), CoreGraphics (event tap, ⌘V), IOKit HID (Caps Lock / keyboard type), **Speech** `SpeechAnalyzer` and **FoundationModels** on macOS 26 (optional engines, `#if canImport` + availability checks), SQLite3, ServiceManagement, Network (model downloads). |

**Not depending on:**
- WhisperKit/SpeakerKit (overlaps 1 + 2).
- mlx-swift (needs Xcode for its Metal shaders).
- sherpa-onnx (large; ONNX Runtime Intel gap).
- transcribe.cpp (watch until 1.0).
- Sparkle and KeyboardShortcuts (the sister apps have their own UpdateKit and hotkey code; KeyboardShortcuts cannot bind Fn alone).
- `ejbills/mediaremote-adapter` (**no licence**). Implement media pause through the documented path, or drop it [U: MediaRemote access is restricted since macOS 15.4].
- `tisfeng/SelectedTextKit` (MIT, but the AX read is about 50 lines; write our own).

### 8.2 Patterns we borrow (learn, then implement ourselves)

| Pattern | From (licence) |
|---|---|
| Hotkey state machine: hold, double-tap lock (≈ 0.3 s), Esc cancel, tested as pure logic | Hex (MIT) |
| Paste: clipboard + CGEvent ⌘V, restore **after the target read the pasteboard** (lazy provider / read notification), configurable delays, never lose text (copy on failure) | Handy (MIT), BetterWispr (Apache-2.0); Wispr Flow does the same |
| AX reads on a serial worker with 250–500 ms messaging timeouts | Dictate Anywhere (MIT), BetterWispr |
| Dictionary: hints + replacement pairs + Jaro-Winkler fuzzy correction + auto-learn from post-paste edits; quick "add misheard word" hotkey | Muesli (MIT), BetterWispr, Whispree (MIT) |
| Voice commands as deterministic rules ("new line", "comma", "scratch that", "press enter") | BetterWispr; Wispr Flow |
| Meeting detection = per-process mic-input listener + bundle-id table + AX browser titles (+ camera signal) + EventKit | BetterWispr, Muesli, meeting-transcriber (MIT/Apache) |
| "Meeting detected" prompt that times out (≈ 30 s) and is suppressed until that app stops using the mic | BetterWispr |
| Global process tap excluding our own PID, private aggregate device with drift compensation; mic = You, system = Others | BetterWispr, AudioCap (BSD-2), Muesli |
| VAD-driven chunk rotation for long recordings; final transcript ready seconds after stop; re-transcribe with another model | Muesli, Meetily (MIT) |
| Dual-track diarization, cross-meeting speaker recognition by embedding cosine similarity, calendar-attendee rename suggestions | meeting-transcriber (MIT), Nutola (MIT) |
| Map-reduce summaries with editable templates (summary / decisions / action items / follow-ups); live draft notes | Nutola, meeting-transcriber, Muesli |
| Ask across meetings with citations over a local index | Muesli |
| First-recording consent acknowledgement; optional chat notice | OpenOats (MIT); Wispr Flow (consent chat message) |
| Plain-file export (Markdown + JSON + m4a per meeting) next to SQLite | Nutola, anarlog (MIT) |
| SwiftPM-only build + bundle script + licences copied into `Contents/Resources/Licenses` | BetterWispr `scripts/build-app.sh` (Apache-2.0) |

### 8.3 Risks

1. **System-audio permission cannot be preflighted** with public API. Design onboarding around "start a 1-second test capture" to trigger the prompt, and detect silence or denial heuristically [V AudioCap].
2. **FluidAudio is pre-1.0 and moves fast** (0.12 → 0.17 in months). Pin `exact:`, wrap it behind our `SpeechEngine` / `Diarizer` protocols, and keep whisper.cpp as an independent engine.
3. **Model licences**: CC-BY-4.0 needs attribution (About › Licences); the NVIDIA Open Model License needs its text shipped; never offer Qwen2.5-3B (non-commercial) or non-English legacy Moonshine models.
4. **Intel Macs**: the ANE paths (FluidAudio) are absent or slow. Use whisper.cpp CPU (base/small) for dictation, post-meeting batch transcription, and no live diarization (OpenWhispr hit the same limit).
5. **Binary targets**: verify each checksum with `swift package compute-checksum` before committing; the GitHub `digest` shown here is the zip's sha256. Bump deliberately with a self-test run.
6. **Copyleft contamination**: VoiceInk, FluidVoice, TypeWhisper, Epicenter/Whispering, VoiceTypr, SayIt, Amurex and OverSight are GPL/AGPL. Contributors must not paste from them; review PRs for it.
7. **Some projects need Xcode** (Muesli, OpenOats). Our CLT-only rule holds only with the dependency set above; BetterWispr proves this set builds with `swift build` [V].

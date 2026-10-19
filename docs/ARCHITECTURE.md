# Architecture

Super Flow is a native macOS app written in Swift (Swift 5 language mode on the Swift 6 toolchain), built with SwiftPM
and the Command Line Tools only (no Xcode project, no Metal or Core ML compiler at build time). Deployment target:
macOS 14. It is a regular Dock app with a hub window plus the floating Flow Bar at the bottom centre of the screen;
there is no menu bar item. Everything (speech, cleanup, diarization, notes) runs on the Mac.

The behaviour to build is specified in `docs/specs/behaviour.md`, the look in `docs/specs/ui-reference.md`, the
wording in `docs/specs/strings.md`, the models and engines in `docs/specs/local-models.md`, and the dependency pins
and licence policy in `docs/specs/oss-survey.md`. Section numbers in code comments point into those files.

```
Sources/
  SuperFlowCore/      contracts & shared utilities (no feature logic): domain model, service protocols,
                      Services registry, paths, typed Defaults + every settings key, key-chord codec and
                      shortcut defaults, app-category tables, model catalog + auto-download policy,
                      retention rules, design tokens (SFColor/SFFont/SFMetrics/SFMotion), logging, alerts,
                      permissions, machine info
  FlowStore/          SQLite store (system SQLite3, FTS5): dictations, dictionary, snippets, transforms,
                      meetings (segments, speakers, summary as JSON), action items, retention pruning,
                      damaged-store recovery
  AudioKit/           microphone capture (AVAudioEngine, 16 kHz mono, pre/post-roll), device ranking,
                      level meter, system-audio capture (Core Audio process tap, SCK fallback), mute,
                      cue sounds
  SpeechKit/          ASR engines behind SpeechRecognizing (Parakeet via FluidAudio, whisper.cpp; Apple
                      SpeechTranscriber optional), VAD, diarization, priority queue; ModelManaging:
                      catalog, automatic background downloads, resume, SHA-256, import, delete, disk usage
  CleanupKit/         deterministic text pipeline (commands, snippets, replacements, fillers, self-
                      corrections, lists, casing, cursor-aware joining, guardrails) around the llama.cpp
                      LLM (prefix cache, per-app style), Transforms, Command Mode
  InsertionKit/       CGEventTap hotkeys (Fn hold / double-tap / chords / triple-tap, secure input, stale
                      keys), AX context reader + app classifier, paste-and-restore or AX insertion,
                      verification, edit observation for auto-learn
  FlowBarKit/         the Flow Bar NSPanel: states, waveform, hands-free buttons, meeting chrome, pickers,
                      tooltips, notification cards, meeting-detected prompt, calendar reminder pill,
                      drag-to-edge, "Getting ready… N%" state
  HubKit/             hub window: Home/History, Dictionary, Snippets, Style, Transforms, Scratchpad,
                      Notetaker library + meeting detail + Notepad, My Tasks, Insights, Settings panes,
                      onboarding, permission screens, open at login
  MeetingKit/         meeting detection (mic holders, conferencing apps, browser tabs, EventKit), popup
                      decision, dual-track recording, live transcript, refine + diarization, summary and
                      action items, export, audio/transcript retention
  UpdateKit/          background updates from GitHub Releases: check, SHA-256 and code-signature
                      verification, staging next to the app, swap on quit or while idle
  DictationKit/       the dictation coordinator (DictationControlling): hotkey routing (Fn gestures, Fn+Space and
                      Fn+Control quirks), the capture → recognition → cleanup → insertion → history pipeline,
                      Command Mode, Transforms, the Notetaker shortcut, "Getting ready… N%", every failure as a
                      card, auto-learn; a library so the self-test can drive it end to end
  SuperFlow/          app target: launch sequence, module wiring, main menu, superflow:// routing
  SuperFlowSelfTest/  headless checks (`swift run SuperFlowSelfTest`), per module, plus native smoke tests
```

## Rules

- Feature modules depend **only** on `SuperFlowCore`. They never import each other; they talk through the `Services`
  registry (`Services.speech`, `Services.flowBar`, …).
- Each protocol has one owning module. Its `<Module>Module.install()` registers the implementation in `Services`.
- `SuperFlowCore` is the contract. A change to it (a new method, a new field, a new setting) updates every
  implementation and fake in the same change. Module-private state is declared in the module itself, with the
  module as key prefix: `Key<Double>("updateKit.lastAttempt", …)`.
- UI code and the service protocols are `@MainActor`. Engines (audio, inference, SQLite) do their work off the main
  actor (actors, queues) and hand back values; they never touch `Services` from a background thread.
- Everything is local. The only network use is model downloads and update checks (`PRIVACY.md`). No telemetry.
- No dead code: superseded code, placeholders and their now-unused helpers go in the same change.
- Never mention the reference product in user-facing strings; copy comes from `docs/specs/strings.md` rewritten
  for Super Flow.

## Ownership map (parallel workers)

| Module | Owns (protocols in `Services`) | Spec | Depends on at runtime |
|---|---|---|---|
| FlowStore | `history: HistoryStoring`, `meetings: MeetingStoring` | behaviour §11, §19, §20.8 | — |
| AudioKit | `audio: AudioCapturing` | behaviour §4, §17, §20.4; local-models §2.8, §8.2 | — |
| SpeechKit | `speech: SpeechRecognizing`, `models: ModelManaging` | local-models §2, §5, §8.3–8.5, §9 | audio frames (values), `Services.history` for vocabulary |
| CleanupKit | `cleanup: TextCleaning` | behaviour §8, §10; local-models §3 | `Services.models` for the GGUF location |
| InsertionKit | `insertion: TextInserting`, `context: AppContextReading`, `hotkeys: HotkeyMonitoring` | behaviour §3, §6, §9 | — |
| FlowBarKit | `flowBar: FlowBarPresenting` | behaviour §5, §18; ui-reference §2, §10.2–10.3 | `Services.dictation`, `Services.audio.level` |
| HubKit | `hub: HubPresenting`, `onboarding: OnboardingPresenting` | behaviour §12–§15, §20.5–20.8; ui-reference §3–§6, §10.1, §10.4 | every store and service, read-only |
| MeetingKit | `meetingDetector`, `meetingRecorder`, `summarizer` | behaviour §20; local-models §8 | `audio`, `speech`, `cleanup`, `meetings`, `flowBar`, `hub` |
| UpdateKit | `updates: Updating` | behaviour §1.5 | `dictation`, `meetingRecorder` for the idle gate |
| DictationKit | `dictation: DictationControlling` | behaviour §1, §2, §7, §9.4, §10 | all of the above |
| SuperFlow | — | behaviour §1 | installs every module, then `DictationCoordinator.shared.activate()` |

Each worker replaces the placeholder in `Sources/<Module>/<Module>Module.swift`, keeps `install()` registering the
same services, adds `Sources/SuperFlowSelfTest/<Module>Tests.swift` with a `register<Module>Tests()` function wired in
`main.swift`, and never edits another module. Contract changes go through `SuperFlowCore` with every caller updated.

## Launch sequence

`Sources/SuperFlow/main.swift`:

1. `applicationWillFinishLaunching` installs modules in dependency order: FlowStore → SpeechKit → AudioKit →
   CleanupKit → InsertionKit → MeetingKit → FlowBarKit → HubKit → UpdateKit → DictationKit, sets the main menu, and
   applies the Dock policy (`hideAppInDock`, off by default).
2. `applicationDidFinishLaunching`: retention sweeps (dictation history by the local data policy, meeting audio past
   30 days, transcripts past theirs), `Services.models.startAutomaticDownloads()` (speech models first), hotkeys,
   `DictationCoordinator.shared.activate()` (listens to hotkeys, warms the installed engines, follows model installs,
   points out a 🌐-key setting that collides with Apple's dictation), meeting detection when set to "Notify me", the
   Flow Bar in its resting state (hidden until onboarding completes), onboarding or the hub, `Services.updates.start()`.
3. Reopening the app shows the hub. `superflow://open[/<page>]`, `start-hands-free`, `stop-hands-free` are parsed by
   `AppRoute`.

## Dictation pipeline (DictationKit)

```
hotkeys (InsertionKit) ─► HotkeyRouter (pure: event + state → intent) ─► DictationCoordinator
   key-down: context.snapshot() (a password field refuses with a card) · status initializing · flowBar.initializing
             audio.frames (subscribed first, so the 300 ms pre-roll arrives) · audio.startMicrophone() · muteOutput
             cue dictationStart · status listening · flowBar.listening(mode) · cleanup.warm(style, level, category)
   while held: 40 ms frames → speech.transcribeIncrementally(…, .dictation): partials → flowBar.showLiveText (hands-free)
             no frame for 3 s → dismiss(noAudioDuringDictation); 19/20 min warning and stop
   key-up:   150 ms post-roll · stop mic · cue dictationStop · status processing · final transcript
             cleanup.clean(input, budget: 1.0 s short / 2.5 s long; per-app style, style detection, dictionary, snippets)
             insertion.insert(text, actions) · history.save (+ audio .caf, snippet use counts)
   audio:    every frame is appended to Audio/Dictations/<id>.pcm (+ <id>.json) as it arrives, so a crash keeps it; a
             finished dictation turns it into <id>.caf or deletes it; leftovers become History rows at the next launch
   failures: an engine error or a cancel after speaking keeps the audio as a row for "Retry transcript"; a paste that
             lands nowhere gives the user's clipboard back and offers Copy; a save that fails keeps the text for paste-last
             flowBar.cleanupCompleted (2 s) · insertion.observeEdits(30 s) → AutoLearn → dictionary + card
   Command Mode (Fn+Control, or Fn then Control): selectedText at start · instruction → cleanup.transform → replaceSelection
   Transforms (⌥1–⌥3): selectedText → cleanup.transform(prompt) → replaceSelection or clipboard
   model not ready: flowBar.preparing(fraction) from models.readiness(of:), capture starts when it installs
   failures: DictationNotices maps AudioError / SpeechError / InsertionOutcome / TransformError to cards with a fix
```

Fn gestures the event tap produces (InsertionKit) and how the router reads them: Fn then Space is a push-to-talk press
followed by a hands-free press with no release, so the running session turns hands-free; stopping with Fn+Space is a
push-to-talk press (finishes) followed by a hands-free press that lands on a busy session (ignored, and debounced for
500 ms); Fn then Control turns the session into Command Mode; a key that completes no chord inside the first second
dismisses with `other_shortcut`.

Meetings run the same engines through `MeetingKit` with `SpeechPriority.meeting`; dictation pre-empts. The notes
model is a second `LanguageModelRole` on `TextCleaning` (`generate(_:instruction:role:)`), loaded by `MeetingRecorder`
when a meeting starts and shared with cleanup when both settings name the same GGUF.

## Native dependencies

| Dependency | Pin | How |
|---|---|---|
| FluidAudio | `exact: "0.17.7"` (tag `v0.17.7`, revision `503b4bd1`) | SwiftPM source package (tools 5.10 manifest: all traits on, which also links `NemoTextProcessing.xcframework`) |
| whisper.cpp | b5454 (= v1.9.5), `whisper-b5454-xcframework.zip`, sha256 `e57f8c48…92393b` | `binaryTarget(url:checksum:)`, module `whisper` |
| llama.cpp | b11721, `llama-b11721-xcframework.zip`, sha256 `9efc8f94…7460f` | `binaryTarget(url:checksum:)`, module `llama` |

Both xcframeworks are universal dynamic frameworks with `@rpath` install names and Metal embedded as source.
`scripts/build-app.sh` copies the macOS slices into `Contents/Frameworks`, rewrites the executable's rpath to
`@executable_path/../Frameworks`, signs the frameworks, then the bundle. Two copies of ggml live in the process
(one per framework); see local-models §7.3 for the CMake route that removes the duplicate.

## Data

`~/Library/Application Support/Super Flow/`: `store.sqlite` (dictations, dictionary, snippets, transforms, notes,
meetings, action items), `Models/<kind>/…`, `Audio/Dictations/<id>.caf` (`<id>.pcm` + `<id>.json` while recording), `Audio/Meetings/<id>/` (raw 30 s chunks while
recording, `<channel>.m4a` after), `Backup/` (a damaged
store, and the `notes.json` of pre-1.0 builds once imported). The Silero VAD ships inside the app
(`Contents/Resources/Models/vad/`). Preferences in `com.udsy.superflow`. See `PRIVACY.md` for retention and the
download hosts.

## Scripts

`scripts/signing-setup.sh` (once), `scripts/build-app.sh` (`--debug`, `UNIVERSAL=1`; copies the frameworks, sounds
and bundled models, signs, then runs static launch checks: the library-validation entitlement, rpaths, every `@rpath`
dependency present in `Contents/Frameworks`, resources and usage descriptions — the app is never launched by the
build), `scripts/make-dmg.sh`, `scripts/release.sh <version>`, `scripts/install.sh` (served at
https://udsy19.github.io/super-flow/install.sh; `SUPERFLOW_INSTALL_DIR`, `SUPERFLOW_NO_OPEN`), `scripts/make-icon.swift`,
`scripts/make-sounds.swift` (synthesises `Resources/Sounds/*.wav`).

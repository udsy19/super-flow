# Contributing to Super Flow

Thanks for helping. Bug reports, feature ideas, documentation and code are all welcome. This page covers the dev
setup, how the project is laid out, the conventions the code follows, how to run the self-tests, and how releases
are made.

## Dev setup

You need macOS 14 or later and the Swift toolchain from the Command Line Tools (`xcode-select --install`). Xcode is
optional; there's no Xcode project. Apple silicon runs every engine; on Intel the Core ML models are skipped.

```sh
git clone https://github.com/udsy19/super-flow.git && cd super-flow
./scripts/signing-setup.sh      # once: a project-local signing identity in .signing/, so Accessibility and
                                # Microphone grants survive rebuilds
./scripts/build-app.sh --debug  # → build/Super Flow.app
open "build/Super Flow.app"
```

`swift build` alone compiles everything (including the self-tests) without making an app bundle. The first build
downloads the whisper.cpp and llama.cpp xcframeworks (checksums pinned in `Package.swift`) and FluidAudio.

## Project layout

```
Package.swift            SwiftPM manifest: the contracts module, the feature modules, the app and the self-test
Sources/
  SuperFlowCore/         contracts and shared utilities: model, service protocols, Services registry, settings keys,
                         shortcuts, app lists, model catalog, languages, export, design tokens, logging, permissions
  FlowStore/             SQLite + FTS5 store: dictations, dictionary, snippets, transforms, notes, meetings, action items
  AudioKit/              microphone and system-audio capture, levels, output mute, cue sounds
  SpeechKit/             ASR engines (Parakeet, whisper.cpp), VAD, diarization, model manager and automatic downloads
  CleanupKit/            rules + local LLM cleanup, guardrails, Transforms, Command Mode, the notes model role
  InsertionKit/          hotkey event tap, app context reader, paste-and-restore insertion, edit observation
  FlowBarKit/            the Flow Bar panel, every state, cards and the meeting prompt
  HubKit/                the hub window: pages, Settings, onboarding, permission screens
  MeetingKit/            meeting detection, recording, speakers, notes, retention
  UpdateKit/             background updates
  DictationKit/          the dictation coordinator: hotkeys → capture → recognition → cleanup → insertion → history
  SuperFlow/             app target: launch, wiring, menu, URL routing
  SuperFlowSelfTest/     headless checks: one file per module plus the end-to-end run
Resources/               Info.plist, entitlements, cue sounds, the bundled Silero VAD
scripts/                 build-app, make-dmg, release, install, signing-setup, make-icon, make-sounds
docs/                    ARCHITECTURE.md and specs/ (the behaviour, UI, strings and models the app follows)
website/                 the GitHub Pages site (static HTML)
.github/                 CI (build + self-tests on macOS), Pages deployment, issue and PR templates
```

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the modules fit together, the launch sequence, the
dictation pipeline and the data layout.

## Conventions

- **Modules depend only on `SuperFlowCore`** and talk through the `Services` registry; they never import each
  other. A new contract goes in Core with every implementation and every fake in the self-test updated in the same
  change.
- **Settings are typed `Defaults` keys** in `SuperFlowCore/Settings.swift` with their default values. Module-private
  state uses the module name as a prefix (`meetingKit.neverAskApps`).
- **UI code and the service protocols are `@MainActor`.** Engines (audio, inference, SQLite) work off the main actor
  and hand back values.
- **Everything is local.** The only network use is model downloads and update checks, each behind its switch and
  described in PRIVACY.md. No telemetry, ever.
- **Models are pinned**: single files by SHA-256, Core ML sets by repository commit; licences in THIRD_PARTY_NOTICES.md.
  Nothing non-commercial.
- **Design tokens come from `SuperFlowCore/Theme.swift`**, which mirrors `docs/specs/ui-reference.md`.
- **No dead code.** When you replace or remove behaviour, delete the old implementation, its helpers and its tests
  in the same change.
- **Wording** follows `docs/specs/strings.md`, rewritten for Super Flow; never name the reference product in the UI.
- `swift build` must be **warning-free**.

## Self-tests

The Command Line Tools ship no XCTest, so tests are an executable with a small `check(_:_:)` harness:

```sh
swift run SuperFlowSelfTest
```

Each module registers its cases in `Sources/SuperFlowSelfTest/<Module>Tests.swift`; `EndToEndTests.swift` drives the
real coordinator with fakes, and, when real models are available, the real speech and cleanup engines on synthetic
speech (`say -o`, never played) through to a private pasteboard and the SQLite history, plus a two-track meeting with
the notes model. Point the real-model cases at local copies of the models:

```sh
SUPERFLOW_DEV_MODELS=/path/with/ggml-and-gguf:/path/with/parakeet-tdt-0.6b-v3 swift run SuperFlowSelfTest
```

Tests never open the microphone, tap system audio, post key events, show windows, read the general pasteboard or use
your real Application Support folder: they use throwaway folders, a defaults suite of their own and private named
pasteboards. Add cases for any new logic.

Offscreen renders of the hub and the Flow Bar (for design review) go to `$SUPERFLOW_RENDER_DIR` when set.

## Pull requests

1. One change per pull request, with a clear description of what it does and why. Link the issue if there is one.
2. `swift build` compiles without warnings and `swift run SuperFlowSelfTest` passes.
3. UI changes come with a render, and follow `docs/specs/ui-reference.md`.
4. Behaviour changes update `docs/specs/behaviour.md` and get a line in CHANGELOG.md under *Unreleased*.
5. Network, permission or data-handling changes update PRIVACY.md.

The pull request template has this as a checklist.

## Reporting bugs

Use the [bug report template](https://github.com/udsy19/super-flow/issues/new/choose). Logs are in Console.app,
filtered by `com.udsy.superflow`. Please don't paste transcripts you wouldn't want public. Security issues go through
[SECURITY.md](SECURITY.md), not the tracker.

## Releases

Maintainers only. Releases are built on the maintainer's Mac and published to GitHub Releases:

1. Add the version's section to CHANGELOG.md (the release notes come from it).
2. `./scripts/release.sh <version>` bumps `Resources/Info.plist`, commits, builds the universal DMG with
   `make-dmg.sh`, tags `v<version>`, and creates the GitHub release with `SuperFlow-<version>.dmg` and a stable
   `SuperFlow.dmg` (which the installer and the website link to) plus the DMG's SHA-256 in the notes.
3. Running copies pick the release up through UpdateKit, which checks that SHA-256 and the code signature before
   installing.

The website deploys from `website/` on every push to `main` (`.github/workflows/pages.yml`); `scripts/install.sh`
is published at the site root.

## Code of conduct

Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

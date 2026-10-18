# Super Flow

Voice dictation and a meeting Notetaker for macOS that run entirely on your Mac. Hold **Fn** and speak into any app;
press **⌥M** to take notes in a meeting. Speech recognition, cleanup, speaker labels and summaries use local models
(Parakeet, Whisper, Qwen) and nothing leaves the machine. Open source, MIT.

> Status: foundation. The package builds, the native engines load, and the module contracts are in place; the
> features are being built module by module (see `docs/ARCHITECTURE.md`).

## Install

```sh
curl -fsSL https://udsy19.github.io/super-flow/install.sh | bash
```

Or download `SuperFlow.dmg` from the latest GitHub release. Requires macOS 14 or later.

## Build from source

Command Line Tools only (no Xcode needed):

```sh
swift build                  # debug build
swift run SuperFlowSelfTest  # headless checks
scripts/signing-setup.sh     # once: a project-local signing identity so privacy grants persist across builds
scripts/build-app.sh         # build/Super Flow.app
```

## Documents

- `docs/ARCHITECTURE.md`: modules, ownership and rules.
- `docs/specs/`: behaviour, UI reference, strings, local models and the open-source survey the rebuild follows.
- `PRIVACY.md`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`.

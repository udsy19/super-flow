# Architecture: one codebase, two editions

- Compile-time condition `APP_STORE` (`swift build -c release -Xswiftc -DAPP_STORE`). Without it the direct edition builds exactly as before.
  `SuperFlowCore.Distribution.isAppStore` exposes it to UI code; behaviour that must not exist in the Store binary uses `#if`.
- Build: `DISTRIBUTION=appstore ./scripts/build-app.sh` → `build/appstore/Super Flow.app` (ad-hoc signed, sandboxed);
  `scripts/package-appstore.sh` re-signs with Store identities and runs `productbuild`. SwiftPM stays the build system; no Xcode project.
- Bundle id: direct `com.udsy.superflow`, Store `com.udsy.superflow.appstore` (one variable, `STORE_BUNDLE_ID` in `scripts/build-app.sh`). Both can be installed side by side; data, defaults and TCC grants are separate (TCC grants do not transfer between editions).

## What differs in the Store edition

| Area | Direct | Store |
|---|---|---|
| Updater (UpdateKit: GitHub Releases, DMG download, `ditto` swap) | on | **compiled out** (`#if !APP_STORE` around the whole module; Settings › Updates hidden; build fails if the GitHub releases URL is in the binary) |
| Model downloads | automatic after install | off until the user accepts a size-disclosed prompt (onboarding footer / Settings › Models); explicit per-model download buttons still work |
| Download origin | Hugging Face or `modelMirrorURL` default | fixed `https://huggingface.co`; mirror ignored |
| Core ML set integrity | hashes read from the HF tree API at a pinned commit | every file must match a SHA-256/blob-SHA-1 compiled into `Sources/SpeechKit/PinnedModelFiles.swift` |
| Accessibility gate for pasting | `AXIsProcessTrusted` | `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` (AX inspection of other apps does not work sandboxed) |
| Insertion | paste (⌘V) or AX write | paste (⌘V) or **copy-only** ("Paste automatically" switch in Settings › System) |
| Permission buttons (Accessibility, Input Monitoring) | prompt first, Settings on 2nd click | prompt, and open System Settings at once when not granted (the prompt agent is sandbox-denied, see test-results.md) |
| Data import | – | Settings › System › "Import from Super Flow (direct download)" |
| Apple Events | entitlement present but unused | removed |
| Diagnostics | – | `--sandbox-probe [--probe-models]` headless probe, compiled only with `-DSANDBOX_PROBE` (`PROBE=1`, build/appstore-probe); build-app.sh fails if a release Store binary contains it |
| AX inspection of other apps (focused field, cursor context, window titles, AX value insertion) | on | **compiled out**; `InsertionMethod.accessibility` doesn't exist; Context awareness hidden; build fails on any `_AXUIElement` import |

## Data import
`SuperFlowCore.DataImport`: the user picks the direct edition's folder in an NSOpenPanel pre-pointed at the real
`~/Library/Application Support/Super Flow` (resolved via `getpwuid`, since `NSHomeDirectory()` is the container). It is copied
(never moved) to `<container>/Library/Application Support/Super Flow (import)`; optionally the direct edition's preferences plist is
picked and its keys copied into the Store defaults, except `DataImport.storeOwnedKeys` (download consent, insertion method,
mirror, context awareness, updater state). After the swap, every imported model is re-hashed against the pinned hashes and
removed if it doesn't match (`ModelManager.removeUnverifiedModels`). The app quits; on next launch, before the database opens, the staged folder
replaces the Store data, and the previous Store data is kept as `Super Flow (before import <date>)`. No container-migration.plist.

## Meeting detection without Apple Events
Detection never used Apple Events: it reads Core Audio process objects (`kAudioHardwarePropertyProcessObjectList`,
`kAudioProcessPropertyIsRunningInput`) to see which conferencing app holds the microphone, `NSRunningApplication`, browser window
titles through AX (direct only: compiled out of the Store edition, so browser-based meetings are not auto-detected there;
native apps are), and EventKit. The probe confirmed Core Audio process objects are readable in the sandbox.

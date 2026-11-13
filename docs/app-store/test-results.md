# Test results — 2026-11-12, macOS 26.5.1 arm64, Command Line Tools only (no Xcode), no signing identities

Runs 1–2 used the Store binary as first built (probe then compiled into it; since moved behind `-DSANDBOX_PROBE`, see review fixes below): `DISTRIBUTION=appstore ./scripts/build-app.sh` → `build/appstore/Super Flow.app`
(ad-hoc signed, App Sandbox entitlement enforced; `libsystem_secinit … AppSandbox` in the log), launched with
`open -n -W "build/appstore/Super Flow.app" --args --sandbox-probe [--probe-models]`. The probe
(`Sources/SuperFlow/SandboxProbe.swift`) calls the production services and writes
`~/Library/Containers/com.udsy.superflow.appstore/Data/tmp/sandbox-probe.json`.

## Build
- `DISTRIBUTION=appstore ./scripts/build-app.sh` → "Static launch checks passed" (sandbox/audio/network entitlements present; no
  disable-library-validation / apple-events / temporary-exception / get-task-allow; bundle id `com.udsy.superflow.appstore`; no
  GitHub-updater strings: `strings … | grep -ci "api.github.com\|hdiutil\|UpdateInstaller"` → 0; quarantine xattrs stripped).
- Direct edition: `./scripts/build-app.sh` → static checks pass (unchanged); `swift build -c release --product SuperFlowSelfTest && .build/release/SuperFlowSelfTest` → "All self-tests passed." (model-dependent cases skipped: no dev models).
- `./scripts/package-appstore.sh` without credentials → exit 2, `error: missing APPSTORE_APP_IDENTITY APPSTORE_INSTALLER_IDENTITY APPSTORE_PROVISIONING_PROFILE.`

## Probe run 2 (`--probe-models`), 18:00–18:06 EST (test WAV: `say -v Samantha -o test.aiff "Um, so I think we should, uh, ship the quarterly report on Friday. Actually no, let's ship it on Monday after the review."` → `afconvert -f WAVE -d LEI16@16000 -c 1`, 7.9 s, copied into the container's tmp)

| Step | Result |
|---|---|
| paths | home = container; support = `<container>/Library/Application Support/Super Flow`; direct-edition folder resolved to the real `~/Library/Application Support/Super Flow` |
| direct folder readable without selection | **false** (sandbox refuses, as expected → import must go through NSOpenPanel) |
| microphone | status notDetermined (new ad-hoc cdhash); `requestAccess` → TCC `AUTHREQ_PROMPTING service=kTCCServiceMicrophone` (prompt shown, unanswered in 5 s); AVAudioEngine start succeeded |
| system audio | method `processTap`; `AudioHardwareCreateProcessTap` + private aggregate device **created in the sandbox**; coreaudiod raised `AUTHREQ_PROMPTING service=kTCCServiceAudioCapture`. No extra entitlement needed beyond the usage string |
| meeting signals | `kAudioHardwarePropertyProcessObjectList`: OSStatus 0, 39 process objects; 133 running apps visible; Calendar status readable (notDetermined) |
| Input Monitoring | `CGPreflightListenEventAccess`=false; `CGRequestListenEventAccess`=false (no prompt observed) |
| listen-only CGEventTap | `CGEvent.tapCreate(.listenOnly)` returned a tap object |
| hotkeys service | throws "needs accessibility access" (no Input Monitoring/Accessibility grant) — expected |
| Accessibility | `AXIsProcessTrusted`=false; `AXIsProcessTrustedWithOptions(prompt)`=false; `CGRequestPostEventAccess`=false. **Sandbox denial:** `deny(1) mach-lookup com.apple.universalaccessAuthWarn` → no prompt is shown to a sandboxed app; the app now opens System Settings instead |
| insertion without grant | `notInserted("accessibility_not_trusted")` — returned at the trust guard before any event was built; with `CGPreflightPostEventAccess`=false nothing was posted. This call was removed from the probe afterwards (no synthetic input from automated runs) |
| data import (fixture inside container) | staged to `Super Flow (import)`, source kept; staging removed after the probe |
| download whisper base (60 MB) | ok, 5 s, SHA-256 verified, in container |
| download Parakeet v3 Core ML set (470 MB) | ok, 44 s, every file matched `PinnedModelFiles` |
| download diarization (22 MB) | ok, 7 s |
| download Qwen3.5 0.8B GGUF (533 MB) | ok, 74 s |
| transcribe, Parakeet (FluidAudio/ANE) | "Um, so I think we should, uh, ship the quarterly report on Friday. Actually no, let's ship it on Monday after the review." — 67.8 s **including first-run Core ML/ANE compilation** |
| transcribe, whisper.cpp (Metal) | "UMM, so I think we should, A, ship the quarterly report on Friday, actually no, let's ship it on Monday after the review" — 1.57 s incl. load |
| diarize | 1 segment, 1 speaker (single synthetic voice) |
| LLM cleanup, llama.cpp Qwen3.5 0.8B | "So I think we should ship the quarterly report on Friday. Actually no, let's ship it on Monday after the review." — 0.89 s, `usedLLM` true |

Sandbox denials for the whole run (`log show --predicate 'sender == "Sandbox"'`, SuperFlow only):
```
18:01:19.008 SuperFlow(34897) deny(1) mach-lookup com.apple.universalaccessAuthWarn   (x2: AX / post-event prompt agent)
18:04:06.524 SuperFlow(34897) deny(1) file-issue-extension target:/ extension-class:com.apple.app-sandbox.read   (during model load; harmless, nothing failed)
```
No file-read/write denials: models, Core ML compiled caches, database and audio all stayed in the container.
Nothing was written to `~/Library/Application Support/FluidAudio`, `~/.cache` or `~/Library/Caches/FluidAudio` (checked: absent).

## Probe run 1 (no models), 17:58 EST
Same permission results. During this run a person at the Mac answered the Microphone and System Audio Recording prompts:
TCC.db shows `com.udsy.superflow.appstore | kTCCServiceMicrophone | 2 (allowed) | 2 (user)` at 17:58:59 and
`kTCCServiceAudioCapture | 2 | 2` at 17:59:02; `requestAccess` returned true and the AVAudioEngine capture and the process tap ran.
(The ad-hoc rebuild changed the code hash, so run 2 was asked again.)

## Synthetic input / GUI automation
None was run: no osascript/System Events, no CGEvent posting, no typing into panels. The only insertion call (probe runs at
17:58 and 18:01 EST) stopped at the trust guard. The direct self-test uses a fake inserter.

## Needs a human run (exact script)
1. `ADHOC=1 ./scripts/package-appstore.sh && open "build/appstore/Super Flow.app"`
2. Onboarding: Download → models land in the container. Grant Microphone.
3. Click Accessibility → System Settings opens → add/enable Super Flow (use "+" if not listed). Same for Input Monitoring.
4. TextEdit: hold Fn, speak, release → verify the text pastes (CGEventPost ⌘V under sandbox) and that the Fn tap (listen-only) fires.
5. Settings › System › Paste automatically off → dictate → "Copied!" and ⌘V pastes.
6. FaceTime/Zoom call → meeting prompt → Record → verify the "Them" track has audio (process tap after the System Audio grant).
7. Settings › System › Import… → pick `~/Library/Application Support/Super Flow` → (optional) `~/Library/Preferences/com.udsy.superflow.plist` → app quits → reopen → history present; direct folder untouched.
8. Remove `com.apple.security.device.microphone` (or `audio-input`) and repeat step 2 to learn which key the sandbox checks.

## Review fixes (2026-11-12, later): self-tests and binary checks
Toolchain: `export DEVELOPER_DIR=/Library/Developer/CommandLineTools` (Xcode 26.6 was installed mid-session, licence not accepted).
- Store self-tests: `swift build -c release -Xswiftc -DAPP_STORE --scratch-path .build-appstore --product SuperFlowSelfTest`, run under
  `sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))'` so any real request would fail → **All self-tests passed**
  (129 cases). Store-specific cases assert the Store behaviour instead of the direct one: downloads default off (Core.settingsDefaults),
  mirror ignored + unpinned set refused (SpeechKit.storeFixedOriginAndPins replaces the two mirror cases), unverified folder import refused
  (SpeechKit.importAndDelete), consent given explicitly before the queue test (SpeechKit.automaticQueue); UpdateKit cases are compiled out.
  The mock server now also answers huggingface.co, so no case can reach the network. The first Store run without these changes tried
  real huggingface.co requests from the mirror cases (blocked by sandbox-exec: "Operation not permitted").
- Direct self-tests: `swift build -c release --product SuperFlowSelfTest && .build/release/SuperFlowSelfTest` → 135 passed, 1 failed:
  `MeetingKit.recordEndToEnd` track lengths [13.44, 13.4] vs the 0.5 s tolerance (timing under load; untouched by this branch);
  re-run alone 3/3 passed.
- Release Store binary: `nm -u … | grep -c _AX` → **0** (no AXUIElement*, not even AXIsProcessTrusted); imports `_CGEventPost`,
  `_CGPreflightPostEventAccess`, `_CGRequestPostEventAccess` for the paste path. `nm … | grep -c SandboxProbe` → **0**; the
  `PROBE=1` test-bed build → 80. build-app.sh now fails a Store build on either. Store `NSAccessibilityUsageDescription`: "Super Flow
  uses Accessibility only to paste your dictated text into the app you are typing in, by sending the paste shortcut (⌘V) when you
  finish speaking, and to copy text you have selected (⌘C) when you ask it to rewrite that text. It never reads the content of other apps."
- Direct binary still imports 6 `_AXUIElement*` symbols (unchanged behaviour).
- `SpeechKit.freeBytesBeforeFolderExists`: the test is identical on `main` (unchanged by this branch until this fix). It compared two
  reads of the volume's free space for equality; any write in between makes them differ (measured: 46 766 363 136 vs 46 766 359 040).
  With other work on the disk it failed 15/15 in isolation in both the direct and Store binaries; it passed in the earlier full direct run
  only because the disk happened to be quiet. So **yes, it fails on main too** under disk activity. Fixed to accept a 256 MB tolerance.

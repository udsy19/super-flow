# Super Flow — Mac App Store edition

**Status: FUNCTIONAL VALIDATION PENDING** (code complete; credentials also required). Core paths proven in the sandboxed
ad-hoc build: model downloads into the container with pinned hashes, Parakeet + whisper.cpp transcription, diarization,
llama.cpp cleanup, microphone capture, Core Audio process-tap creation, Core Audio meeting signals, data-import staging.
Pending a human: paste and Fn hotkey after manually granting Accessibility / Input Monitoring; system-audio content.

## Commands
```bash
# Store edition, ad-hoc signed and sandboxed, for local testing
ADHOC=1 ./scripts/package-appstore.sh                 # → build/appstore/Super Flow.app
# Probe test bed (never the release binary): -DSANDBOX_PROBE, written to build/appstore-probe/
PROBE=1 DISTRIBUTION=appstore ./scripts/build-app.sh
open -n -W "build/appstore-probe/Super Flow.app" --args --sandbox-probe [--probe-models]
cat ~/Library/Containers/com.udsy.superflow.appstore/Data/tmp/sandbox-probe.json
/usr/bin/log show --last 10m --predicate 'sender == "Sandbox"' | grep 'SuperFlow('

# Store package (needs credentials)
APPSTORE_APP_IDENTITY="Apple Distribution: … (TEAMID)" \
APPSTORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: … (TEAMID)" \
APPSTORE_PROVISIONING_PROFILE=~/Downloads/SuperFlow_MAS.provisionprofile \
UNIVERSAL=1 ./scripts/package-appstore.sh            # → dist/SuperFlow-AppStore-<version>.pkg

# Direct edition (unchanged)
./scripts/build-app.sh            # same as DISTRIBUTION=direct
```
`--probe-models` downloads ~1.1 GB into the container; delete
`~/Library/Containers/com.udsy.superflow.appstore/Data/Library/Application Support/Super Flow/Models` afterwards.

Docs: [architecture](architecture.md) · [entitlements](entitlements.md) · [models](model-and-asset-strategy.md) ·
[privacy](privacy-and-permissions.md) · [licences](dependency-and-license-audit.md) · [compliance](compliance-matrix.md) ·
[tests](test-results.md) · [ASC metadata](app-store-connect.md) · [review notes](review-notes.md) · [blockers](known-blockers.md) ·
[inventory.json](inventory.json)

# Entitlements

| Entitlement | Direct (`Resources/SuperFlow.entitlements`) | Store (`Resources/SuperFlow-AppStore.entitlements`) | Why |
|---|---|---|---|
| `com.apple.security.app-sandbox` | – | yes | Required for the Mac App Store. |
| `com.apple.security.device.audio-input` | yes | yes | Dictation and meeting microphone. |
| `com.apple.security.device.microphone` | – | yes | Kept alongside `audio-input` per the shared brief (#10) until an experiment removes one; the probe run with both captured audio. Removing one and re-running `--sandbox-probe` is a cheap follow-up. |
| `com.apple.security.network.client` | n/a (unsandboxed) | yes | Model downloads from `https://huggingface.co` (passive data, hashes pinned in source). |
| `com.apple.security.personal-information.calendars` | n/a | yes | EventKit read access for meeting titles/attendees. |
| `com.apple.security.files.user-selected.read-write` | n/a | yes | Meeting export (NSSavePanel) and "Import from Super Flow (direct download)" (NSOpenPanel). |
| `com.apple.security.automation.apple-events` | yes | **no** | Audit: no Apple Event is sent anywhere in the code (no NSAppleScript/SBApplication/AE calls); the direct entitlement is vestigial. The Store Info.plist also drops `NSAppleEventsUsageDescription`. |
| `com.apple.security.cs.disable-library-validation` | yes | **no** | Needed in direct only because the frameworks are signed with a self-signed identity. In the Store build `whisper.framework` and `llama.framework` are signed with the same Apple Distribution identity as the app. |

Not used in Store: `network.server`, `inherit`, `allow-unsigned-executable-memory`, `allow-jit`, any `temporary-exception`.
The Store edition has no helper executables (the direct edition's updater runs `/usr/bin/ditto`/`hdiutil`/`/bin/sh`; UpdateKit is compiled out).

`scripts/build-app.sh` (`DISTRIBUTION=appstore`) fails the build if the signed app lacks the sandbox/audio/network entitlements
or carries `disable-library-validation`, `allow-unsigned-executable-memory`, `apple-events`, `temporary-exception` or `get-task-allow`.
`scripts/package-appstore.sh` adds `com.apple.application-identifier` and `com.apple.developer.team-identifier` from the provisioning profile at signing time.

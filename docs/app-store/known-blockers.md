# Known blockers

## Credentials (blocks submission)
- No Apple Distribution / 3rd Party Mac Developer Installer identity, no Mac App Store provisioning profile, no Xcode on this Mac.
  `scripts/package-appstore.sh` fails with an exact message until `APPSTORE_APP_IDENTITY`, `APPSTORE_INSTALLER_IDENTITY`,
  `APPSTORE_PROVISIONING_PROFILE` are set. Upload/validation (Transporter) not attempted. Register `com.udsy.superflow.appstore`.
- Direct edition: still self-signed and not notarized (unchanged). Developer ID + notarization needs a Developer ID identity.

## Functional validation pending (needs a human)
- Paste via CGEventPost and Fn push-to-talk via listen-only event tap under the sandbox **after** Accessibility / Input Monitoring
  are granted manually (the sandbox blocks the prompt agent, so these can't be granted from the app's prompt). test-results.md has the script.
- Process-tap audio content after the System Audio grant (tap creation proven; audio frames not verified).
- Which of `device.audio-input` / `device.microphone` the sandbox checks.

## Material product changes needing owner approval
1. **Auto-paste review risk (2.4.5).** Store keeps ⌘V posting behind Accessibility and adds a copy-only mode. If Review rejects,
   switch the Store default to copy-only (`Defaults[.insertionMethod] = .copyOnly`).
2. **Models no longer download automatically** in the Store edition; the user must accept the size-disclosed download (4.2.3).
3. **Lost in the sandbox:** context awareness (reading text around the cursor), AX value-write insertion, AX secure-field detection
   (Secure Event Input still blocks), browser-tab meeting detection (window titles via AX), Globe-key settings hint. Native meeting
   apps are still detected through Core Audio.
4. **No in-app updates**; the "Install updates automatically" setting is hidden.
5. **Prompts:** Accessibility and Input Monitoring cannot show a system prompt sandboxed — the app sends users to System Settings.
6. Nemotron (NVIDIA Open Model License) and CC-BY models in a Store app: owner to confirm licence acceptance/attribution placement.
7. Data import replaces the Store edition's data with the imported copy (previous Store data kept beside it).
8. Added "Dictation › Start Notetaker" menu item (both editions) so meetings are reachable without a global shortcut.

# App Store Connect metadata (draft)

- **Name:** Super Flow · **Subtitle:** Private voice dictation & meeting notes
- **Bundle ID:** `com.udsy.superflow.appstore` (register before upload; change `STORE_BUNDLE_ID` in scripts/build-app.sh if different)
- **SKU:** superflow-mac · **Primary category:** Productivity · **Secondary:** Business
- **Price:** owner decision · **Age rating:** 4+ (no user-generated content shared, no web access)
- **Minimum macOS:** 14.0 (system-audio tap needs 14.4; on 14.0–14.3 meetings record the microphone only)

**Description (draft, grounded in shipped features)**
Super Flow turns your voice into clean text in any app, on your Mac. Hold Fn (or your shortcut), speak, let go: your words are
transcribed on-device by Parakeet or Whisper, tidied by a local language model (fillers and self-corrections removed, your
dictionary and snippets applied) and pasted where you were typing — or copied to the clipboard if you prefer.
Meeting Notetaker records your microphone and your Mac's audio as separate tracks, transcribes them live, separates speakers and
writes a summary with action items — all locally. Nothing you say leaves the Mac; there is no account and no tracking.
Speech and text models (about 1.8 GB for dictation) download from Hugging Face after you agree.

**Keywords:** dictation, speech to text, transcription, voice typing, meeting notes, whisper, offline, private, notetaker
**Support URL:** https://github.com/udsy19/super-flow/issues · **Marketing URL:** https://udsy19.github.io/super-flow/
**Privacy policy URL:** needs a hosted page (PRIVACY.md content) — owner.

**App Privacy (nutrition label):** Data Not Collected.

**Export compliance:** uses only OS-provided HTTPS and hashing; owner to confirm "exempt" (see dependency-and-license-audit.md).

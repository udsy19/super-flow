# Notes for App Review (draft)

Super Flow is an on-device dictation and meeting transcription app. No account or login is needed.

**Getting the models (required to review dictation/meetings).** On first launch, the onboarding window shows
"They download once from Hugging Face: <size>" with a **Download** button (≈1.8 GB on a 16 GB Apple-silicon Mac). Tap it.
Dictation works as soon as the 60 MB Whisper base or 470 MB Parakeet model is in (progress at the bottom of onboarding and in
Settings › Models, where every model also has its own download button and size). Models are data files only (Core ML / ggml /
GGUF weights), pinned by SHA-256 in the app; no code is downloaded.

**Permissions to grant for a full review**
1. Microphone — system prompt on first dictation.
2. Accessibility — used only to post ⌘V (paste) into the app you are typing in. macOS does not show a prompt for sandboxed apps;
   Super Flow opens System Settings › Privacy & Security › Accessibility: enable "Super Flow". To review **without**
   Accessibility: Settings › System › "Paste automatically" off — the text is placed on the clipboard and the Flow Bar says "Copied!".
3. Input Monitoring — to notice Fn/your shortcut being held (listen-only). Enable "Super Flow" in the pane the app opens.
4. System Audio Recording (meetings only) — prompted when the first meeting recording starts.
5. Calendar (optional) — names meetings.

**Try dictation:** open TextEdit, hold **Fn**, say "Hello from Super Flow, um, testing one two three", release. Clean text appears.
**Try meetings:** menu Dictation › **Start Notetaker**, or press **⌥M** (Join meeting / start Notetaker; needs Input Monitoring) or join a FaceTime/Zoom call — Super Flow asks before recording. The Flow Bar shows the
recording state and timer; stop to see transcript, speakers and summary.

Accessibility is used only to deliver the user's own dictated text to the focused app at the user's explicit request (holding the key).

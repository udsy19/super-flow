# Models and assets (Store edition)

**Bundled:** Silero VAD ggml (0.9 MB) and FluidAudio's resource bundle. Everything else is a post-install data download.

**Rules the Store edition enforces** (guidelines 2.5.2, 4.2.3, 2.4.5(iv)):
- Data only: Core ML model folders, ggml/GGUF weight files. No code, scripts or dylibs are ever downloaded.
- Fixed origin: `https://huggingface.co` (the `modelMirrorURL` override is ignored in the Store build).
- Integrity pinned in source: single files by SHA-256 (`ModelCatalog.swift`); Core ML sets by repository commit *and* every file's
  SHA-256 (LFS) or Git blob SHA-1 in `Sources/SpeechKit/PinnedModelFiles.swift` (generated from the HF tree API at the pinned
  commits, 215 entries). A file that is not pinned or does not match aborts the download (`ModelError.checksumMismatch`).
- Consent: `autoDownloadModels` defaults to **off** in the Store build. Onboarding and Settings › Models show
  "Super Flow runs its speech and text models on this Mac. They download once from Hugging Face: <size>." with
  **Download <size>** / **Not now**. Each model row in Settings › Models also has its own download button showing its size.
- Location: `~/Library/Containers/com.udsy.superflow.appstore/Data/Library/Application Support/Super Flow/Models/<kind>/…`
  (resolved through `FileManager.urls(for: .applicationSupportDirectory)`, i.e. inside the container). FluidAudio's own
  downloader/default cache (`~/Library/Application Support/FluidAudio`) is never used: the engines load from explicit directories.
  Verified in the sandbox run: all files landed in the container, no file-write denials.
- Downloads use the explicit queue (user tap) or the automatic queue (after consent), which pauses on hotspot/Low Data,
  Low Power, low disk and while dictating.

## Size and memory table

| Model | Role | Download | RAM floor (catalog `minRAM`) | Preset |
|---|---|---|---|---|
| Parakeet TDT 0.6B v3 (Core ML, int8 encoder) | dictation ASR, 25 languages | 470 MB | 1 GB | Apple silicon default |
| Nemotron Speech Streaming EN 0.6B | live English ASR | 627 MB | 1 GB | opt-in |
| Whisper base q5_1 | starter / Intel ASR | 60 MB | 256 MB | all |
| Whisper small q5_1 | Intel ASR | 190 MB | 512 MB | Intel > 8 GB |
| Whisper large-v3-turbo q5_0 | 99-language fallback | 574 MB | 1 GB | on demand |
| Qwen3.5 0.8B Q4_K_M | Intel meeting notes | 533 MB | 1 GB | Intel |
| Qwen3.5 2B Q4_K_M | cleanup | 1.28 GB | 2 GB | Apple silicon standard/32 GB; meetings on light |
| Qwen3.5 4B Q4_K_M | meeting notes, transforms | 2.74 GB | 4 GB | Apple silicon ≥ 12 GB |
| Qwen3 4B Instruct 2507 Q4_K_M | alternative notes | 2.50 GB | 6 GB | opt-in |
| Diarization Community-1 (Core ML) | speakers | 22 MB | 256 MB | meetings |
| LocalVQE 1.3 (Core ML) | echo removal | 20 MB | 128 MB | Apple silicon meetings |
| Silero VAD v6.2.0 | voice detection | bundled 0.9 MB | 16 MB | all |

Presets (ModelCatalog.preset): Apple silicon standard (12–24 GB) asks for **1.81 GB** for dictation
(Parakeet + Whisper base + Qwen3.5 2B) and **2.78 GB** for meetings (diarization + LocalVQE + Qwen3.5 4B).

## Reviewability (2.4.5(iv), brief #4)
Every model-dependent feature is reachable by the reviewer: onboarding's **Download** button (or Settings › Models › each row's
download button) fetches the models; dictation works as soon as Whisper base (60 MB) or Parakeet (470 MB) is in. See review-notes.md.

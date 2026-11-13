# Dependency and licence audit (Store edition)

| Component | Version | Licence | Kind | Bundled | Sandbox |
|---|---|---|---|---|---|
| FluidAudio | 0.17.7 (exact pin) | Apache-2.0 | SwiftPM source package (Core ML ASR/VAD/diarization/LocalVQE) | statically linked; `FluidAudio_FluidAudio.bundle` resources | OK: models loaded from explicit container paths, FluidAudio's own downloader never called (verified: nothing written outside the container; no sandbox file denials) |
| NemoTextProcessing.xcframework (FluidInference/text-processing-rs v0.3.1) | 0.3.1 | Apache-2.0 | binary target via FluidAudio | statically linked | OK |
| whisper.cpp + ggml | b5454 xcframework (SHA-256 pinned in Package.swift) | MIT | dynamic framework | `Contents/Frameworks/whisper.framework` | OK: loads and transcribes in sandbox (test-results.md). Store signs it with the app's team identity; no library-validation exception |
| llama.cpp + ggml | b11721 xcframework (SHA-256 pinned) | MIT | dynamic framework | `Contents/Frameworks/llama.framework` | OK: GGUF loads and generates in sandbox, Metal offload |
| SQLite3 | macOS SDK | public domain / system | system library | – | OK |
| Silero VAD v6.2.0 (ggml) | – | MIT | data | `Contents/Resources/Models/vad/` (0.9 MB) | OK |

No GPL/LGPL/AGPL code is linked (GPL projects in docs/specs/oss-survey.md were read for behaviour only). No Homebrew paths (build check enforces).
No code is downloaded after install; downloads are model weights only (below).

## Downloaded models

| Model | Licence | Notes for the Store |
|---|---|---|
| Parakeet TDT 0.6B v3 (Core ML, FluidInference) | CC-BY-4.0 | Attribution shown in About › Licences and THIRD_PARTY_NOTICES.md. OK for commercial use. |
| Nemotron Speech Streaming EN 0.6B (Core ML) | NVIDIA Open Model License | Commercial use permitted; licence text ships in `Contents/Resources/Licenses/`. Opt-in only. Owner should confirm acceptance of NVIDIA's terms for a paid/Store listing. |
| Whisper base / small / large-v3-turbo (ggml) | MIT | – |
| Qwen3.5 0.8B / 2B / 4B, Qwen3-4B-Instruct-2507 (GGUF, Unsloth) | Apache-2.0 | – |
| Speaker diarization Community-1 (pyannote/WeSpeaker/BUT PLDA, Core ML) | CC-BY-4.0 | Attribution in-app. |
| LocalVQE 1.3 | Apache-2.0 | – |
| Apple SpeechAnalyzer (macOS 26) | OS component | Nothing downloaded by the app. |

Export compliance (brief #7): the app implements no encryption of its own; it uses HTTPS (URLSession) and CryptoKit SHA-256/SHA-1 for integrity only. Hashing is exempt; HTTPS via the OS is exempt. Suggested answer: `ITSAppUsesNonExemptEncryption = NO` — owner to confirm before adding the key (not added).

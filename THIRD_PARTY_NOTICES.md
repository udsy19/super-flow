# Third-party notices

Super Flow is MIT-licensed (see `LICENSE`). It links the libraries below and downloads the models below at the
user's request or automatically after install (see `PRIVACY.md`). Licence texts of the libraries are in their
repositories; the app's About › Licences pane shows the same list with the attribution each licence asks for.

## Libraries

| Component | Version | Licence | Notes |
|---|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 0.17.7 | Apache-2.0 | Parakeet ASR, Silero VAD, speaker diarization, LocalVQE on Core ML. Includes `NemoTextProcessing.xcframework` (FluidInference/text-processing-rs v0.3.1, Apache-2.0). Its own `ThirdPartyLicenses` folder lists the licences of the code it vendors. |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) + ggml | b5454 (v1.9.5), `whisper-b5454-xcframework.zip` | MIT | Copyright (c) 2023-2024 The ggml authors |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) + ggml | b11721, `llama-b11721-xcframework.zip` | MIT | Copyright (c) 2023-2024 The ggml authors |
| Apple frameworks (AVFoundation, Core Audio, ScreenCaptureKit, EventKit, Speech, FoundationModels, Core ML, Metal, SQLite3) | macOS SDK | Apple SDK licence | System frameworks |

## Models (downloaded, never bundled except Silero VAD)

Core ML sets are pinned to a repository commit and single files to a SHA-256 (`Sources/SuperFlowCore/ModelCatalog.swift`).
The Silero VAD ggml file (`ggml-org/whisper-vad`, MIT) ships inside the app at `Contents/Resources/Models/vad/`.

| Model | Licence | Attribution |
|---|---|---|
| NVIDIA Parakeet TDT 0.6B v3 (Core ML conversion by Fluid Inference) | CC-BY-4.0 | "Parakeet TDT 0.6B v3" by NVIDIA, licensed under CC-BY-4.0; the Core ML files are a modified conversion by Fluid Inference. |
| NVIDIA Nemotron Speech Streaming EN 0.6B, 1120 ms tier (Core ML conversion by Fluid Inference, `FluidInference/nemotron-speech-streaming-en-0.6b-coreml`) | NVIDIA Open Model License (October 24, 2025) | Licensed by NVIDIA Corporation under the NVIDIA Open Model License. The agreement and this notice ship in the app (`Contents/Resources/Licenses/NVIDIA-Open-Model-License.txt`, from `Resources/Licenses/`). Downloaded only when the user chooses the engine; use follows NVIDIA's Trustworthy AI terms. |
| OpenAI Whisper large-v3-turbo, small, base (ggml conversions from `ggerganov/whisper.cpp`) | MIT | Copyright (c) 2022 OpenAI |
| Silero VAD v6.2.0 (ggml conversion, `ggml-org/whisper-vad`; Core ML via FluidAudio) | MIT | Copyright (c) 2020-present Silero Team |
| Qwen3.5-0.8B, Qwen3.5-2B, Qwen3.5-4B, Qwen3-4B-Instruct-2507 (GGUF quantisations by Unsloth) | Apache-2.0 | Copyright Alibaba Cloud / the Qwen team |
| Speaker diarization Community-1 set (pyannote segmentation, WeSpeaker ResNet34-LM embedding, BUT Speech@FIT PLDA; Core ML conversions by Fluid Inference) | CC-BY-4.0 | Attribution to pyannote, WeSpeaker, BUT Speech@FIT and Fluid Inference; the files are modified Core ML conversions. |
| LocalVQE 1.3 (`FluidInference/localvqe-coreml`) | Apache-2.0 | Fluid Inference |

Models the catalog deliberately does not offer: Qwen2.5-3B-Instruct (Qwen Research licence, non-commercial),
NVIDIA Sortformer v1 (CC-BY-NC-4.0), NVIDIA Canary-1B (CC-BY-NC-4.0), legacy non-English Moonshine models
(non-commercial). Apple's SpeechTranscriber (macOS 26) is part of the operating system; nothing of it ships or
downloads with Super Flow.

## Study-only projects

Projects surveyed in `docs/specs/oss-survey.md` under GPL/AGPL (VoiceInk, FluidVoice, TypeWhisper, Whispering,
VoiceTypr, SayIt, Amurex, OverSight) were read for behaviour only; no code from them is in this repository.

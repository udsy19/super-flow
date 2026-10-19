# A second speech-to-text engine (besides Parakeet and Whisper)

Status: research, 19 Oct 2026; integrated the same day (`NemotronEngine`, `AppleSpeechEngine`, `SpeechService`,
`ModelCatalog.nemotronStreamingEN` / `.appleSpeech`, Settings › Models "Dictation engine"). Deviations from the plan:
the settings use the owner's labels "Parakeet (multilingual, default)" / "Nemotron (English, fastest, live text)";
the lead-in silence is fed before every stream (not only when the pre-roll is short); Apple's engine counts as an
engine only once chosen (it may make the OS download assets) and supports 30 locales of 10 languages. Measured in
the self-test on the M4 Pro with 300 ms lead-in clips: tail 21–24 ms, 0 word errors, a partial per 1.12 s chunk.

Related: `local-models.md` §2 (speech options) and §6 (licences), `oss-survey.md` §2 and §7.

## 0. Decision

**Add NVIDIA Nemotron Speech Streaming EN 0.6B, 1120 ms tier, through the FluidAudio 0.17.7 we already pin.** Offer
it as a user-selectable "live" English engine next to Parakeet.

- **Accuracy:** 1.9% WER on our test set. Parakeet v3 scores 1.4%; every other candidate scores 3.8% or worse.
- **Key-up latency:** 18 ms, because it streams while the key is held. Parakeet's batch pass at key-up takes 43 ms.
- **Live text:** true streaming partials (`TranscriptionEvent.partial`).
- **No new dependency.** It needs no package, binary target or build step, and it runs on the Neural Engine.
- **Cost:**
  - English only;
  - 627 MB download;
  - the NVIDIA Open Model License, whose text and notice we must ship. `local-models.md` §6 already accepts this
    licence for Nemotron and Parakeet EOU.

**Also add Apple SpeechAnalyzer / SpeechTranscriber** as an optional zero-download engine on macOS 26.
- It compiles with the Command Line Tools for arm64 and x86_64 behind `if #available(macOS 26, *)`.
- It covers 30 locales and its models are managed by the OS.
- On our set: 4.3% WER batch, 5.2% streaming, with 53 ms key-up latency.

**Runner-up: Moonshine Medium Streaming** (MIT code and weights, 269 MB, 3.8% WER).
- It is the pick if the owner wants only OSI-licensed weights.
- Its integration costs more: we would host our own repackaged xcframework (§5.3), and it runs on the CPU.

**Rejected:**

| Candidate | Why |
|---|---|
| Kyutai STT | No Swift or C integration path; 1–2.6 B parameters; English/French only |
| IBM Granite Speech | 2 B+ parameters; Transformers runtime |
| NVIDIA Canary-1B | Non-commercial licence |
| Canary-1B-v2 | Its first Core ML load did not finish compiling in 30 minutes |
| sherpa-onnx streaming Zipformer | 11.8% WER; no punctuation or casing |
| Cohere Transcribe | 5 GB Core ML |

## 1. How the candidates were tested

**Machine.** M4 Pro, macOS 26 (SDK 26.5), Command Line Tools only (Swift 6.3.3), on battery-unrestricted power.

**Audio.** 48 clips, 2.6–9.9 s each (mean 4.3 s, 206 s in total, 578 reference words):
- 32 clips from `say -o`: 16 dictation-style sentences, each in two of 8 system voices (Samantha, Daniel, Karen,
  Rishi, Moira, Tessa, Reed, Shelley; US, UK, AU, IN, IE and ZA accents). They include names (Siobhan), jargon
  (Kubernetes, refactor, onboarding), times and numbers.
- 16 utterances of 3–10 s from the 73-utterance LibriSpeech validation sample
  (`hf-internal-testing/librispeech_asr_dummy`). This is LibriVox public-domain audio; the corpus is CC-BY-4.0.

Every clip was run twice: as generated, and with **400 ms of leading silence**. The silence stands in for the app's
300 ms microphone pre-roll (`DictationLimits.preRoll`). The pre-roll numbers are the realistic ones.

**WER.** Word error rate after Whisper-style normalisation: lower case, no punctuation, digits and times spelled out
("3:30" = "three thirty", "12%" = "twelve percent", "2nd" = "second"). At 578 words, one error is 0.17 points, so read
differences under about 1 point as noise.

**Latency.**
- **Batch:** the whole clip transcribed after key-up, with a warm engine. This is how Parakeet and Whisper work today.
- **Tail:** for streaming engines. The clip is fed in 100 ms buffers as if the key were held, and tail is the time from
  the last buffer to the final text, i.e. what the user waits after releasing the key.
- **Feed:** the compute spent while the key is held, as a share of real time.

**Harnesses** (all in a scratch folder, all built with CLT):
- a FluidAudio probe for Parakeet, Nemotron and Canary, against a copy of the pinned 0.17.7 source;
- a `swiftc`-built SpeechAnalyzer probe;
- a C probe linked against `libmoonshine.a`;
- the sherpa-onnx prebuilt command-line tool.

## 2. Results

| Engine | Licence | Download | WER no pre-roll | **WER with pre-roll** | Key-up latency p50 / p90 | Feed (while held) | Partials | Languages |
|---|---|---|---|---|---|---|---|---|
| Parakeet TDT 0.6B v3 (today's default) | CC-BY-4.0 | 470 MB | 1.9% | **1.4%** | batch 43 / 46 ms | — | no | 25 European |
| **Nemotron Speech Streaming EN 0.6B, 1120 ms** | NVIDIA Open Model License | 627 MB | 3.3% | **1.9%** | **tail 18 / 20 ms** (batch 78 / 118) | 1.6% RT, ANE | yes, every 1.12 s | en |
| Moonshine Medium Streaming (245 M) | MIT | 269 MB | 3.5% | **3.8%** | tail 76 / 113 ms (batch 218 / 350) | 12% RT on ~7 CPU cores | yes | en (other languages: separate small/tiny models) |
| Moonshine Small Streaming (123 M) | MIT | 142 MB | 4.5% | 4.7% | tail 53 / 74 ms | 8% RT, CPU | yes | en |
| Apple SpeechTranscriber (`.transcription` / `.progressiveTranscription`) | OS | 0 (OS assets) | 3.3% / 4.2% | 4.3% / 5.2% | batch 94 / 114 ms; tail 53 / 73 ms | OS process | yes (volatile results) | 30 locales |
| sherpa-onnx streaming Zipformer en 2023-06-26 (int8) | Apache-2.0 | 341 MB | 11.8% | — | 170 / 230 ms (CLI, whole clip) | CPU | yes | en, upper case, no punctuation |
| Canary-1B-v2 int4 (FluidAudio beta) | CC-BY-4.0 | 566 MB | not measured | — | first load still compiling for the ANE after 30 min (system compiler at 100% CPU, 3.7 GB RSS) | — | no (fixed 15 s window) | 25 European |

**Where the engines go wrong** (pre-roll runs):
- **All engines:** "pushed" heard as "push" (Daniel), "fix" as "figs" (Moira), "flight" as "fly it"/"flower" (Rishi).
- **Siobhan:** heard as "Siobon"/"Shavon" (Parakeet), "Shervon" (Nemotron), "Sharon" (Moonshine), "Chevron"
  (Apple). Every engine needs the dictionary pass. Moonshine and Apple can bias toward known words (§5.3, §6);
  Nemotron cannot.
- **Kubernetes:** Parakeet got it right. Nemotron wrote "Cuban Eats", Apple "Cuban needs"/"Gubernitz", Moonshine
  "cubanese".
- **Nemotron without pre-roll** dropped the first word of 7 of the 48 clips ("The", "Our", "Could"). With 400 ms of
  leading silence it dropped none. It also leaves out the final period, which our cleanup adds.
- **Moonshine's batch API** invents endings ("at 3.30 p.m", "at 720"). Its streaming path does not, so use the stream
  only.
- **Apple** writes times as bare digits ("at 330", "at 915").

**Memory (peak RSS of the probe process):**
- Parakeet: 523 MB.
- Nemotron: 665 MB.
- Moonshine Medium: 1.65 GB (ONNX Runtime arenas; batch and stream sessions both loaded).
- Apple: 22 MB, because the model runs in a system process.

**First load:**
- Nemotron: 13.8 s the first time (ANE compile, cached by the OS), then 0.2 s.
- Parakeet: 20–43 s the first time, then cached.
- Moonshine: 0.1–0.9 s.

## 3. Licence check

All weights are downloaded at run time from the pinned repository; none ship inside the app bundle. If we ever mirror
them, the redistribution terms below apply to us.

| Model | Licence | Our MIT app | Redistributing weights | Verdict |
|---|---|---|---|---|
| Nemotron Speech Streaming EN 0.6B (`nvidia/nemotron-speech-streaming-en-0.6b`; Core ML `FluidInference/…-coreml`) | NVIDIA Open Model License (Oct 2025) | Yes: "commercially usable", separate from our code licence | Allowed with a copy of the agreement and the notice "Licensed by NVIDIA Corporation under the NVIDIA Open Model License" | **Accept.** Ship the text. Caveats: the grant is revocable on patent/copyright suits or on bypassing model guardrails; NVIDIA may update it for legal or regulatory reasons; use must follow NVIDIA's Trustworthy AI terms. |
| Moonshine streaming (all sizes), English Tiny/Base | MIT | Yes | Yes | Accept. Avoid the legacy non-English Base/Tiny models: Moonshine Community Licence, non-commercial. |
| Apple SpeechAnalyzer | System framework | Yes | n/a | Accept. |
| Canary-1B (`nvidia/canary-1b`) | CC-BY-NC-4.0 | **No** | — | **Reject.** |
| Canary-1B-v2, Canary-1B-flash, Canary-180M-flash, Canary-Qwen-2.5B | CC-BY-4.0 | Yes | Yes, with attribution | Licence OK; rejected on runtime (§0). |
| Kyutai stt-1b-en_fr, stt-2.6b-en | CC-BY-4.0 | Yes | Yes | Licence OK; rejected on runtime and size. |
| IBM Granite Speech 3.3 2B / 8B | Apache-2.0 | Yes | Yes | Licence OK; rejected on size and runtime. |
| Cohere Transcribe 03-2026 | Apache-2.0 | Yes | Yes | Licence OK; 5 GB Core ML. |
| SenseVoice Small | FunASR model licence (custom) | Unclear | Unclear | Not pursued. |
| Nemotron 3.5 ASR Streaming Multilingual 0.6B (Core ML repo) | OpenMDW-1.1 (Core ML repo card) | Yes | Yes | Not measured: about 2.5 GB per language-group folder. A candidate for a later "live, 8 languages" engine. |

## 4. Why each of the others was rejected

- **Moonshine Medium Streaming** (runner-up).
  - *For it:* MIT weights, the smallest download, live partials, and decoder biasing (`keyterms`) that maps directly
    onto the personal dictionary.
  - *Against it:* twice Nemotron's errors on our set. It computes for 12% of real time while the key is held,
    spread over about 7 CPU cores (battery and fan on long dictations).
  - *Build cost:* the official SwiftPM manifest points at a `Moonshine.xcframework.zip` (v0.0.8) that returns 404.
    Current releases ship only `moonshine-voice-macos-arm64.tar.gz`: a static library plus a C header, arm64 only,
    with ONNX Runtime linked in (96 MB unpacked). We would have to repackage it as an xcframework and host it
    ourselves (§5.3).
- **Apple SpeechTranscriber.** Kept as an optional engine (§6). It is not the main second engine because it needs
  macOS 26, has a higher WER, and offers no language auto-detection.
- **Kyutai STT** (delayed-streams-modeling).
  - Runtimes are PyTorch, MLX in Python, and a Rust server built on candle. There is no Swift or C API.
  - The Rust crate could be built with cargo and linked over a C shim under CLT, but that is a new toolchain in the
    build, plus 1–2.6 B parameters (about 2 GB at bf16).
  - English and French only.
- **IBM Granite Speech 3.3.** 2 B and 8 B speech-LLMs on Transformers or vLLM, with no Core ML or ggml path we can
  build with CLT. Too slow for push-to-talk, too big for the default disk budget.
- **NVIDIA Canary.**
  - Canary-1B is non-commercial.
  - Canary-1B-v2 (CC-BY-4.0) has a FluidAudio beta port with a fixed 15 s window, so short utterances pay for 15 s
    of encoder. Its first Core ML load kept the system ANE compiler busy for over 30 minutes without finishing, and
    the probe was stopped. That is not acceptable on a user's first run.
  - The flash models have no Core ML or ggml port.
- **sherpa-onnx streaming Zipformer.** 11.8% WER (17.8% on the `say` clips): it was trained on LibriSpeech only and
  outputs upper-case text without punctuation. The rest of the pipeline relies on the engine's punctuation.
- **Cohere Transcribe 03-2026.** Excellent leaderboard WER, but 2 B parameters and a 5 GB q8 Core ML set.

## 5. Integration plan: Nemotron Speech Streaming EN

### 5.1 Package

No change. `FluidAudio` stays `exact: "0.17.7"`. The engine is `StreamingNemotronAsrManager` (public in 0.17.7):
- `loadModels(from:)`, `process(audioBuffer:)`, `appendAudio(_:)`, `processBufferedAudio()`;
- `getPartialTranscript()`, `setPartialCallback(_:)`;
- `finish()`, `finishWithTokenTimings()`, `reset()`, `cleanup()`.

The probe built against a copy of exactly that source with `swift build -c release` under CLT.

### 5.2 Model catalog entry

The Core ML set is pinned by repository commit, like Parakeet:

```swift
/// Live English dictation: cache-aware streaming RNNT, partial text every 1.12 s, ANE (stt-second-engine.md).
public static let nemotronStreamingEN = ModelDescriptor(
    id: "nemotron-speech-streaming-en-0.6b-1120ms", kind: .asr, name: "Nemotron Speech Streaming 0.6B (English)",
    engine: "fluidaudio-nemotron",
    bytes: 626_803_815,
    repository: "FluidInference/nemotron-speech-streaming-en-0.6b-coreml",
    revision: "e673531caa6d25ab7baf5a8c14c9b99ba1551838",
    licence: "NVIDIA Open Model License",
    attribution: "NVIDIA Nemotron Speech Streaming EN 0.6B. Licensed by NVIDIA Corporation under the NVIDIA Open Model "
        + "License; Core ML conversion by Fluid Inference (modified).",
    languages: ["en"], minRAM: 1 * gib)
```

**Files** (repository subfolder `nemotron_coreml_1120ms/`, 626,803,815 bytes in total):

| File | Bytes | Note |
|---|---|---|
| `encoder/encoder_int8.mlmodelc/weights/weight.bin` | 589,403,200 | LFS oid prefix 409df1105de0bed2 |
| `decoder_joint.mlmodelc` | 17.9 MB | |
| `decoder.mlmodelc` | 14.4 MB | |
| `joint.mlmodelc` | 3.4 MB | |
| `preprocessor.mlmodelc`, `tokenizer.json`, `metadata.json` | small | |

Each LFS object is verified by its SHA-256 oid from the tree API at the pinned revision, as `ModelFiles` already does
for Parakeet.

**Two small changes in `ModelFiles.swift`:**
1. `ModelDescriptor` gets an optional `subfolder` (`"nemotron_coreml_1120ms"`). The repository listing keeps only
   paths under it and strips the prefix, so the installed folder `Models/asr/<id>/` holds exactly what `loadModels(from:)`
   reads.
2. `requiredEntries` returns `ModelNames.NemotronStreaming.requiredModels` when `engine == "fluidaudio-nemotron"`,
   instead of keying on `kind == .asr`.

**Presets.** Not in any preset. It is an opt-in download from Settings › Models, so the default disk budget does not
change.

### 5.3 Adapter (`SpeechRecognizing`)

**New `Sources/SpeechKit/NemotronEngine.swift`**, an actor shaped like `ParakeetEngine`:
- `load()`: `StreamingNemotronAsrManager().loadModels(from: directory)`.
- `warm()`: one second of silence through `process` and `finish`, then `reset()`. This builds the ANE plans before
  the first dictation; the first load compiles for about 14 s and is then cached by the OS.
- `transcribe(_ clip)` for batch use (Retry, imports): `reset()` → `process(whole clip)` → `finish()` →
  `Transcript(language: "en")`.
- A streaming session for dictation:
  - `begin()`: `reset()`. Prepend 400 ms of zeros when the first clip carries less than 300 ms of pre-roll. Without
    lead-in the model dropped the first word in 7 of 48 clips.
  - `append(clip)`: `process(audioBuffer:)`, then return `getPartialTranscript()`.
  - `end()`: `finish()` → final text.

**`SpeechService` changes:**
- `canRun`: `engine == "fluidaudio-nemotron"` needs Apple silicon, like Parakeet.
- `prepare(modelID:)`: create, load and warm `NemotronEngine`, as for Parakeet.
- `engine(for:)`: Nemotron only when every selected language is English. Otherwise fall back to Parakeet or Whisper
  through the existing logic, so choosing Nemotron never breaks other languages.
- `transcribeIncrementally`, when the active engine is Nemotron:
  - skip the VAD segmentation;
  - feed every `AudioClip` straight into the session;
  - yield `.partial(text)` whenever the partial changes, about every 1.12 s;
  - after the stream ends, yield one `.segment` and `.final(Transcript)`.

  Silero still decides "no speech" from the full clip, as today: under 250 ms of speech means `SpeechError.noSpeech`.
- Meetings keep Parakeet or Whisper. Nemotron is English only, and the meeting pipeline is batch over VAD segments.
- `TranscriptionOptions.vocabulary` is ignored. Nemotron streaming has no biasing in FluidAudio 0.17.7, so the
  dictionary pass in CleanupKit (`cleanup-quality.md` §5 P2.10) covers it.

**Self-test** (`SpeechKitTests`): when `SUPERFLOW_DEV_MODELS` contains `nemotron-speech-streaming-en-0.6b-1120ms/`:
- transcribe two `say -o` clips with 300 ms of lead-in;
- assert at most one word error each;
- assert the first word is present;
- assert the tail is under 100 ms.

### 5.4 Licences and notices

- Add the NVIDIA Open Model License text and the notice line to `THIRD_PARTY_NOTICES.md` and About › Licences
  (`ModelDescriptor.attribution`). `local-models.md` §5.5 already plans a slot for it.
- Show the licence name in the model row before download.

### 5.5 Settings wording (proposed copy for `strings.md`; layout stays with `ui-reference.md`)

| Element | Text |
|---|---|
| Engine name | Nemotron Live (English) |
| Engine subtitle | Shows your words as you speak and finishes fastest. English only. |
| Size/licence line | 627 MB · NVIDIA Open Model License |
| Parakeet subtitle, for contrast | Most accurate. 25 European languages. |
| Hint when the user's languages include more than English | Nemotron Live only understands English. Other languages use Parakeet. |
| Licence row in About | Nemotron Speech Streaming EN 0.6B — Licensed by NVIDIA Corporation under the NVIDIA Open Model License. |

## 6. Optional engine: Apple SpeechAnalyzer (macOS 26)

- **Build.** The probe (`import Speech`; `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, `AnalyzerInput`)
  compiled with `swiftc -target arm64-apple-macos14.0`, and type-checked for `x86_64-apple-macos14.0`, under CLT
  SDK 26.5, behind `if #available(macOS 26, *)`. No Xcode was needed.
- **Engine `AppleSpeechEngine`** (SpeechKit):
  - Uses `SpeechTranscriber(locale:preset:)`: `.transcription` for batch, `.progressiveTranscription` for live
    partials.
  - Installs the locale assets with `AssetInventory.assetInstallationRequest(supporting:)` when the user picks the
    engine. The OS owns the download and shares it across apps, so it costs no app disk.
  - Biases toward dictionary words with `AnalysisContext.contextualStrings`, set through `SpeechAnalyzer.setContext`.
  - Streaming: buffers in `bestAvailableAudioFormat(compatibleWith:)`, `start(inputSequence:)`, and
    `finalizeAndFinishThroughEndOfInput()` at key-up. Measured tail p50 53 ms.
- **Catalog.** A descriptor with `engine: "apple"`, `bytes: 0`, `url` and `repository` nil, and the 30
  `SpeechTranscriber.supportedLocales`. `ModelManager` reports it installed when `SpeechTranscriber.isAvailable` and
  the selected locale's assets are present. Hide it below macOS 26.
- **Languages.** One fixed locale per analyzer and no auto-detection. Offer it only when the user has a single
  dictation language in its 30 locales.
- **Measured:** 4.3% WER batch, 5.2% streaming (pre-roll set). No Speech Recognition permission prompt for file or
  buffer input in a command-line process (`local-models.md` §2.2). Re-check inside the signed app.
- **Wording:**
  - Name: "Apple on-device (macOS 26)".
  - Subtitle: "No download. Uses the speech model built into macOS. 30 languages, one at a time."

## 7. If the owner prefers MIT-only weights: Moonshine Medium Streaming plan

**Binary.** Repackage `moonshine-voice-macos-arm64.tar.gz` from release v0.1.5 (26 MB; SHA-256
`51151f98eb1b20b8fc141bab361a1574dbfdbef8300b632ee6679e373112e0f6`) in a release script:
1. Hand-write an xcframework: `Info.plist` with one `macos-arm64` library, plus `libmoonshine.a`, `Headers/` and a
   `module.modulemap` for `moonshine-c-api.h`. `xcodebuild -create-xcframework` is not in CLT, but the format is a plain
   folder.
2. Zip it, upload it to our own GitHub release, and pin it with `.binaryTarget(url:checksum:)`.
3. Link `c++` and the Accelerate framework. Linking only needs `-lc++` and Foundation, CoreML and Accelerate, as the
   probe showed.

The library is arm64 only, so Intel Macs keep Whisper.

**Models.** `https://download.moonshine.ai/model/medium-streaming-en/quantized_26_08_21/`, 269,141,623 bytes:

| File | Bytes | SHA-256 |
|---|---|---|
| `adapter.ort` | 3,651,296 | `3f2a287def57cc094367a0eec3c4f5fc36a32ec420e86764b696920991b20281` |
| `cross_kv.ort` | 11,643,776 | `642f6e21cd305be79342207c6f9e6b681d469d55bc48c72b27b84846fb71fd1e` |
| `decoder_kv.ort` | 146,972,408 | `193bb366492b74fc4ad338c6778e8d8eb916aaa11b5aa264f9057f4db7759486` |
| `encoder.ort` | 94,705,376 | `12915e76ebac7dd287c5ea63965d06103a53ba1ce242a4a34f318f3958c60c37` |
| `frontend.model.ort` | 28,720 | `95768855c70c8251eeecc05fedf69999da1b8ab16f605c9f457fd3354b0ad6b5` |
| `frontend.weights.ort` | 11,889,560 | `5ac941f490cbe035b335b99a414cc393d62d4c6f9f2423495b286870d271d709` |
| `streaming_config.json` | 513 | `28e83b7a28e91472692a035e0dae3116422ae43aeb2bef5ed822c44ce89b88af` |
| `tokenizer.bin` | 249,974 | `6884b35fd6377d4c4d32336a0bc152f36b64d1e45b6503683cdc238250a8472d` |

The catalog needs one more layout kind: a fixed list of single files, each with a URL and SHA-256.

**Adapter.** Use the streaming C API only; the batch call invents endings.
- `moonshine_load_transcriber_from_files(dir, MOONSHINE_MODEL_ARCH_MEDIUM_STREAMING, …)`.
- Per dictation: `moonshine_create_stream`, then `moonshine_start_stream`.
- While the key is held: `moonshine_transcribe_add_audio_to_stream` for each clip, and `moonshine_transcribe_stream`
  about every 500 ms for partials.
- At key-up: `moonshine_stop_stream`, then `moonshine_transcribe_stream`.
- `keyterms` takes the starred dictionary words (`moonshine_transcriber_set_keyterms`). Check that ONNX Runtime's
  thread pool stays at most 4 threads when the app also runs the LLM.

## 8. Rejected or deferred alternatives worth watching

- **transcribe.cpp** (MIT; ships `TranscribeCpp.xcframework.zip`).
  - It covers Moonshine streaming, Nemotron streaming, Canary and Qwen3-ASR on ggml, including an Intel build.
  - If it reaches 1.0 it could replace both the Moonshine repackaging and the Whisper-only Intel path
    (`oss-survey.md` §2).
- **Nemotron 3.5 ASR Streaming Multilingual 0.6B** (OpenMDW-1.1 Core ML card).
  - Live text for en, es, fr, it, pt, de, zh and ja, with an auto mode.
  - Measure it before offering "live" outside English. Its folders are about 2.5 GB, so check whether one tier can be
    fetched on its own.

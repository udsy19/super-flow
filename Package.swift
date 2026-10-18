// swift-tools-version:5.10
import PackageDescription

// Super Flow — on-device voice dictation and meeting Notetaker for macOS. Feature modules depend only on
// SuperFlowCore (the contracts); the app target wires them together through the `Services` registry.
// See docs/ARCHITECTURE.md for who owns what.
let modules = [
    "FlowStore",     // SQLite store: dictation history, dictionary, snippets, meetings, action items, retention
    "AudioKit",      // microphone + system-audio capture, levels, VAD wiring, cue sounds
    "SpeechKit",     // ASR engines behind one protocol (Parakeet via FluidAudio, whisper.cpp), model manager
    "CleanupKit",    // rule-based cleanup + local LLM (llama.cpp): fillers, self-corrections, style, dictionary, snippets, transforms
    "InsertionKit",  // Fn/hotkey event tap, Accessibility context, insertion at the cursor
    "FlowBarKit",    // the floating Flow Bar and all its states, notification cards, meeting prompt
    "HubKit",        // the hub window: home/history, dictionary, snippets, style, notes, meetings library, settings, onboarding
    "MeetingKit",    // meeting detection, dual-track recording, live transcript, diarization, summary, library, export, retention
    "UpdateKit",     // background updates from GitHub Releases: check, verify, stage, swap on quit or when idle
]

let package = Package(
    name: "SuperFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SuperFlow", targets: ["SuperFlow"]),
    ],
    dependencies: [
        // Parakeet TDT v3 ASR (ANE), Silero VAD, speaker diarization, LocalVQE. Apache-2.0. docs/specs/oss-survey.md §8.1.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .target(name: "SuperFlowCore", path: "Sources/SuperFlowCore"),

        // Official release xcframeworks (universal macOS slice, Metal embedded, no Xcode needed). The checksums are
        // the SHA-256 of the release zips, verified with `swift package compute-checksum` (docs/specs/local-models.md §7.3).
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"),
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11721/llama-b11721-xcframework.zip",
            checksum: "9efc8f94a7fb54abb4931bac484a025417cee5bbf8e15ba49b4d9ddef997460f"),

        .target(name: "FlowStore", dependencies: ["SuperFlowCore"], path: "Sources/FlowStore",
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "AudioKit", dependencies: ["SuperFlowCore"], path: "Sources/AudioKit"),
        .target(name: "SpeechKit",
                dependencies: ["SuperFlowCore", "whisper", .product(name: "FluidAudio", package: "FluidAudio")],
                path: "Sources/SpeechKit"),
        .target(name: "CleanupKit", dependencies: ["SuperFlowCore", "llama"], path: "Sources/CleanupKit"),
        .target(name: "InsertionKit", dependencies: ["SuperFlowCore"], path: "Sources/InsertionKit"),
        .target(name: "FlowBarKit", dependencies: ["SuperFlowCore"], path: "Sources/FlowBarKit"),
        .target(name: "HubKit", dependencies: ["SuperFlowCore"], path: "Sources/HubKit"),
        .target(name: "MeetingKit", dependencies: ["SuperFlowCore"], path: "Sources/MeetingKit"),
        .target(name: "UpdateKit", dependencies: ["SuperFlowCore"], path: "Sources/UpdateKit"),

        .executableTarget(name: "SuperFlow", dependencies: ["SuperFlowCore"] + modules.map { .target(name: $0) },
                          path: "Sources/SuperFlow"),
        // Headless checks (Command Line Tools have no XCTest): `swift run SuperFlowSelfTest`.
        .executableTarget(name: "SuperFlowSelfTest", dependencies: ["SuperFlowCore"] + modules.map { .target(name: $0) },
                          path: "Sources/SuperFlowSelfTest"),
    ]
)

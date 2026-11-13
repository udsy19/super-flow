#if APP_STORE && SANDBOX_PROBE
import AppKit
import ApplicationServices
import AVFoundation
import CoreAudio
import EventKit
import SuperFlowCore

/// Compiled only into probe builds (`PROBE=1 DISTRIBUTION=appstore ./scripts/build-app.sh`, which adds -DSANDBOX_PROBE and
/// writes build/appstore-probe/); never into the release Store binary (build-app.sh checks with nm).
/// `--sandbox-probe`: a headless run of the Store edition's sandbox-sensitive paths through the real services, for the
/// App Store test bed (docs/app-store/test-results.md). It never shows UI of its own, writes one JSON report to the
/// container's temporary folder (`sandbox-probe.json`) and quits. Prompts it triggers (Microphone, Accessibility,
/// Input Monitoring) are system dialogs; it records what the API returned without waiting for an answer.
///
/// `--probe-models` also downloads the test models through the real downloader (explicit downloads, checksum-pinned)
/// and runs a file transcription, diarization and an LLM cleanup on `probe.wav` in the same temporary folder.
/// First caller wins (`SandboxProbe.withTimeout`).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    init() {}
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

@MainActor
enum SandboxProbe {
    static var requested: Bool { CommandLine.arguments.contains("--sandbox-probe") }
    private static var withModels: Bool { CommandLine.arguments.contains("--probe-models") }
    private static var report: [[String: String]] = []

    private static func record(_ step: String, _ ok: Bool, _ detail: String) {
        report.append(["step": step, "ok": String(ok), "detail": detail])
        Log.app.info("probe \(step, privacy: .public) ok=\(ok) \(detail, privacy: .public)")
    }

    static func run() {
        Task { @MainActor in
            await probe()
            let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sandbox-probe.json")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: out)
            }
            NSApp.terminate(nil)
        }
    }

    private static func probe() async {
        record("paths", true, "home=\(NSHomeDirectory()) support=\(SuperFlowPaths.support.path) direct=\(Distribution.directEditionSupport.path)")
        record("directEditionReadable", FileManager.default.isReadableFile(atPath: Distribution.directEditionSupport.path),
               "without a user selection the sandbox should refuse this")

        // Microphone: the authorization state, the request (prompt), then a real start of the capture engine.
        record("microphone.status", true, "\(Permissions.microphone.rawValue) (0 notDetermined, 1 restricted, 2 denied, 3 authorized)")
        let granted = await withTimeout(5) { await Permissions.requestMicrophone() }
        record("microphone.request", granted != nil, granted.map { "returned \($0)" } ?? "no answer within 5 s (prompt shown, waiting for a click)")
        do {
            try await Services.audio.startMicrophone()
            record("microphone.start", true, "capture started; running=\(Services.audio.isCapturingMicrophone)")
            try? await Task.sleep(nanoseconds: 500_000_000)
            Services.audio.stopMicrophone()
        } catch {
            record("microphone.start", false, error.localizedDescription)
        }

        // System audio: the Core Audio process tap (macOS 14.4+).
        record("systemAudio.method", true, "\(Services.audio.systemAudioMethod)")
        do {
            try await Services.audio.startSystemAudio()
            record("systemAudio.start", true, "tap running=\(Services.audio.isCapturingSystemAudio)")
            Services.audio.stopSystemAudio()
        } catch {
            record("systemAudio.start", false, error.localizedDescription)
        }

        // Meeting detection's signals: Core Audio process objects (who holds the mic), running apps, Calendar.
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        record("meetings.processObjects", status == noErr, "OSStatus \(status), \(Int(size) / MemoryLayout<AudioObjectID>.size) process objects")
        record("meetings.runningApps", true, "\(NSWorkspace.shared.runningApplications.count) running applications visible")
        record("calendar.status", true, "\(EKEventStore.authorizationStatus(for: .event).rawValue) (0 notDetermined, 3 fullAccess)")

        // Hotkeys: the event tap, Input Monitoring and Accessibility.
        record("inputMonitoring.preflight", true, "CGPreflightListenEventAccess=\(CGPreflightListenEventAccess())")
        record("inputMonitoring.request", true, "CGRequestListenEventAccess=\(CGRequestListenEventAccess())")
        record("postEvents.preflight", true, "CGPreflightPostEventAccess=\(CGPreflightPostEventAccess())")
        do {
            try Services.hotkeys.start()
            record("hotkeys.start", true, "tap mode \(String(describing: Services.hotkeys.tapMode))")
        } catch {
            record("hotkeys.start", false, error.localizedDescription)
        }
        Services.hotkeys.stop()
        let listenTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
                                          callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil)
        record("eventTap.listenOnly", listenTap != nil, listenTap == nil ? "tapCreate returned nil" : "tap created")
        if let listenTap { CFMachPortInvalidate(listenTap) }
        record("accessibility.trusted", true, "AXIsProcessTrusted=\(AXIsProcessTrusted())")
        record("accessibility.requestAX", true,
               "AXIsProcessTrustedWithOptions(prompt)=\(AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary))")
        record("postEvents.request", true, "CGRequestPostEventAccess (Permissions.requestAccessibility)=\(Permissions.requestAccessibility())")
        // Insertion is never exercised here: the probe must not post keystrokes into whatever app has focus. Only the
        // preflight above is reported; pasting is a human-run check (docs/app-store/test-results.md).

        // Data import: stage a fixture copy from inside the container and swap it in, as Settings › System does.
        probeImport()

        if withModels { await probeModels() }
    }

    private static func probeImport() {
        let fm = FileManager.default
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("direct-fixture", isDirectory: true)
        try? fm.removeItem(at: fixture)
        do {
            try fm.createDirectory(at: fixture.appendingPathComponent("Audio/Dictations"), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: fixture.appendingPathComponent("store.sqlite"))
            try Data().write(to: fixture.appendingPathComponent("Audio/Dictations/a.caf"))
            // Its own staging folder: a real import the user staged is never touched.
            let staging = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("probe-import-staging", isDirectory: true)
            try DataImport.stage(from: fixture, to: staging)
            record("import.stage", fm.fileExists(atPath: staging.appendingPathComponent("store.sqlite").path) && fm.fileExists(atPath: fixture.path),
                   "staged at \(staging.path); source kept")
            try fm.removeItem(at: staging)
        } catch {
            record("import.stage", false, error.localizedDescription)
        }
    }

    private static func probeModels() async {
        let ids = [ModelCatalog.whisperBase.id, ModelCatalog.parakeetV3.id, ModelCatalog.diarization.id, ModelCatalog.qwen35_0_8B.id]
        for id in ids where Services.models.state(of: id) != .installed {
            let started = Date()
            do {
                for try await _ in Services.models.download(id) {}
                record("download.\(id)", Services.models.state(of: id) == .installed,
                       "\(String(format: "%.0f", Date().timeIntervalSince(started))) s at \(Services.models.location(of: id)?.path ?? "?")")
            } catch {
                record("download.\(id)", false, error.localizedDescription)
            }
        }
        let wav = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("probe.wav")
        guard let samples = try? AudioClip.samples(of: wav) else {
            record("transcribe", false, "no 16 kHz mono probe.wav in \(NSTemporaryDirectory())")
            return
        }
        let clip = AudioClip(samples: samples)
        var transcript: Transcript?
        for id in [ModelCatalog.parakeetV3.id, ModelCatalog.whisperBase.id] {
            do {
                let started = Date()
                try await Services.speech.prepare(modelID: id)
                let result = try await Services.speech.transcribe(clip, options: TranscriptionOptions(languages: ["en"]), priority: .dictation)
                record("transcribe.\(id)", !result.text.isEmpty,
                       "\(String(format: "%.2f", Date().timeIntervalSince(started))) s: \(result.text)")
                transcript = transcript ?? result
            } catch {
                record("transcribe.\(id)", false, error.localizedDescription)
            }
        }
        do {
            let segments = try await Services.speech.diarize(clip)
            record("diarize", !segments.isEmpty, "\(segments.count) segments, \(Set(segments.map(\.speakerID)).count) speakers")
        } catch {
            record("diarize", false, error.localizedDescription)
        }
        guard let transcript else { return }
        do {
            try await Services.cleanup.prepare(modelID: ModelCatalog.qwen35_0_8B.id, role: .cleanup)
            let started = Date()
            let output = await Services.cleanup.clean(CleanupInput(transcript: transcript), budget: 30)
            record("cleanup.llm", output.usedLLM, "\(String(format: "%.2f", Date().timeIntervalSince(started))) s, "
                   + "skip=\(String(describing: output.skipReason)): \(output.text)")
        } catch {
            record("cleanup.llm", false, error.localizedDescription)
        }
    }

    /// The work's result, or nil when it hasn't answered in time (the work is left running: a permission request can't
    /// be cancelled).
    private static func withTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async -> T) async -> T? {
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            Task { let value = await work(); if once.claim() { continuation.resume(returning: value) } }
            Task { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); if once.claim() { continuation.resume(returning: nil) } }
        }
    }
}
#endif

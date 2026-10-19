import AVFoundation
import Combine
import CryptoKit
import Foundation
import SpeechKit
import SuperFlowCore

// Owned with SpeechKit. Downloads run against an in-process URLProtocol server (no network); speech fixtures are
// synthesised with `say -o` into the temporary folder (nothing is played). Real models are used only when present in
// the folders `SUPERFLOW_DEV_MODELS` names (colon-separated); they are never in the repository.
func registerSpeechKitTests() {
    SelfTest.cases.append(("SpeechKit.brokenModelFallsBack", { MainActor.assumeIsolated { speechBrokenModelFallsBack() } }))
    SelfTest.cases.append(("SpeechKit.languages", { speechLanguages() }))
    SelfTest.cases.append(("SpeechKit.transcriptGuards", { speechGuards() }))
    SelfTest.cases.append(("SpeechKit.vadSegmentation", { speechSegmentation() }))
    SelfTest.cases.append(("SpeechKit.priorityGate", { MainActor.assumeIsolated { speechPriorityGate() } }))
    SelfTest.cases.append(("SpeechKit.modelLayout", { speechModelLayout() }))
    SelfTest.cases.append(("SpeechKit.autoDownloadGate", { speechGate() }))
    SelfTest.cases.append(("SpeechKit.downloads", { MainActor.assumeIsolated { speechDownloads() } }))
    SelfTest.cases.append(("SpeechKit.pauseAndResume", { MainActor.assumeIsolated { speechPauseResume() } }))
    SelfTest.cases.append(("SpeechKit.folderDownloadViaMirror", { MainActor.assumeIsolated { speechFolderDownload() } }))
    SelfTest.cases.append(("SpeechKit.automaticQueue", { MainActor.assumeIsolated { speechAutomaticQueue() } }))
    SelfTest.cases.append(("SpeechKit.importAndDelete", { MainActor.assumeIsolated { speechImportDelete() } }))
    SelfTest.cases.append(("SpeechKit.sileroVAD", { MainActor.assumeIsolated { speechSilero() } }))
    SelfTest.cases.append(("SpeechKit.parakeetFixtures", { MainActor.assumeIsolated { speechParakeet() } }))
    SelfTest.cases.append(("SpeechKit.whisperFixtures", { MainActor.assumeIsolated { speechWhisper() } }))
    SelfTest.cases.append(("SpeechKit.diarizationFixture", { MainActor.assumeIsolated { speechDiarization() } }))
}

// MARK: - Helpers

private extension Data {
    var sha256: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
    var gitBlobSHA1: String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(count)\0".utf8))
        hasher.update(data: self)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private func pattern(_ count: Int, seed: UInt8) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
}

/// Runs the main run loop until `condition` holds or the timeout passes.
@MainActor private func waitUntil(_ timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}

@MainActor private func drain(_ stream: AsyncThrowingStream<DownloadProgress, Error>, timeout: TimeInterval = 30) -> (updates: [DownloadProgress], error: Error?) {
    let result = complete(timeout) { () -> [DownloadProgress] in
        var updates: [DownloadProgress] = []
        for try await update in stream { updates.append(update) }
        return updates
    }
    switch result {
    case .success(let updates)?: return (updates, nil)
    case .failure(let error)?: return ([], error)
    case nil: return ([], URLError(.timedOut))
    }
}

/// An in-process HTTP server for model downloads: byte ranges, one-shot mid-stream failures, slow delivery, statuses.
final class MockModelServer: URLProtocol, @unchecked Sendable {
    struct Resource {
        var data: Data
        var status = 200
        var headers: [String: String] = [:]
        /// Drop the connection after this many body bytes, once.
        var failAfter: Int?
        var chunk = 32 << 10
        var delay: TimeInterval = 0
    }

    static let lock = NSLock()
    nonisolated(unsafe) static var resources: [String: Resource] = [:]
    nonisolated(unsafe) static var requests: [(url: String, range: String?)] = []
    private let stateLock = NSLock()
    private var stopped = false

    static func serve(_ url: String, _ resource: Resource) { lock.withLock { resources[url] = resource } }
    static func ranges(for url: String) -> [String?] { lock.withLock { requests.filter { $0.url == url }.map(\.range) } }

    static func configuration(automatic: Bool) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockModelServer.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let range = request.value(forHTTPHeaderField: "Range")
        let resource: Resource? = Self.lock.withLock {
            Self.requests.append((url.absoluteString, range))
            let found = Self.resources[url.absoluteString]
            Self.resources[url.absoluteString]?.failAfter = nil
            return found
        }
        guard let resource else { return respond(status: 404, headers: [:], body: Data(), resource: Resource(data: Data())) }
        guard resource.status == 200 else { return respond(status: resource.status, headers: [:], body: Data(), resource: resource) }
        var offset = 0
        if let range, range.hasPrefix("bytes="), let start = Int(range.dropFirst(6).split(separator: "-").first ?? "") { offset = start }
        if offset >= resource.data.count, offset > 0 {
            return respond(status: 416, headers: ["Content-Range": "bytes */\(resource.data.count)"], body: Data(), resource: resource)
        }
        var headers = resource.headers
        headers["Content-Length"] = "\(resource.data.count - offset)"
        if offset > 0 { headers["Content-Range"] = "bytes \(offset)-\(resource.data.count - 1)/\(resource.data.count)" }
        respond(status: offset > 0 ? 206 : 200, headers: headers, body: resource.data.subdata(in: offset..<resource.data.count), resource: resource)
    }

    private func respond(status: Int, headers: [String: String], body: Data, resource: Resource) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let deliver = { [self] in
            var sent = 0
            while sent < body.count {
                if stateLock.withLock({ stopped }) { return }
                if let failAfter = resource.failAfter, sent >= failAfter {
                    // Like a real dropped connection: the bytes already sent reach the client before the error.
                    Thread.sleep(forTimeInterval: 0.05)
                    client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                    return
                }
                let end = min(body.count, sent + resource.chunk, resource.failAfter.map { max($0, sent + 1) } ?? Int.max)
                client?.urlProtocol(self, didLoad: body.subdata(in: sent..<end))
                sent = end
                if resource.delay > 0 { Thread.sleep(forTimeInterval: resource.delay) }
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        if resource.delay > 0 || resource.failAfter != nil { DispatchQueue.global().async(execute: deliver) } else { deliver() }
    }

    override func stopLoading() { stateLock.withLock { stopped = true } }
}

@MainActor final class FakeEnvironment: DownloadEnvironment {
    var conditions: DownloadConditions
    var onChange: (() -> Void)?

    init(networkUsable: Bool = true, lowPowerMode: Bool = false, freeBytes: Int64 = 100 << 30) {
        conditions = DownloadConditions(networkUsable: networkUsable, lowPowerMode: lowPowerMode, freeBytes: freeBytes)
    }

    func set(_ change: (inout DownloadConditions) -> Void) {
        change(&conditions)
        onChange?()
    }
}

private func testModel(_ id: String, data: Data, kind: ModelKind = .llm, sha: String? = nil) -> ModelDescriptor {
    ModelDescriptor(id: id, kind: kind, name: id, engine: "llama", bytes: Int64(data.count), url: URL(string: "https://models.test/\(id).bin"),
                    sha256: sha ?? data.sha256, licence: "MIT")
}

@MainActor private func testManager(_ catalog: [ModelDescriptor], plan: [ModelDescriptor] = [], environment: FakeEnvironment? = nil)
    -> (ModelManager, URL) {
    let root = SuperFlowPaths.support.appendingPathComponent("models-\(UUID().uuidString)", isDirectory: true)
    let manager = ModelManager(catalog: catalog, root: { root }, environment: environment ?? FakeEnvironment(), plan: { plan },
                               retryDelays: [0.01, 0.01, 0.01],
                               sessionConfiguration: MockModelServer.configuration)
    return (manager, root)
}

// MARK: - Pure logic

private func speechLanguages() {
    check(SupportedLanguages.base("en-US") == "en" && SupportedLanguages.base("pt_BR") == "pt" && SupportedLanguages.base("FR") == "fr", "base codes")
    check(SpeechLanguages.requested(selected: ["en-US", "en", "fr"], autoDetect: false) == ["en", "fr"], "selected languages, de-duplicated")
    check(SpeechLanguages.requested(selected: ["en"], autoDetect: true).isEmpty, "auto-detect asks for everything")
    check(SupportedLanguages.parakeetCovers(["en", "de", "uk"]) && !SupportedLanguages.parakeetCovers(["en", "hi"]) && !SupportedLanguages.parakeetCovers([]),
          "Parakeet covers its 25 languages only, never auto-detect")
    check(TextLanguage.identify("Bonjour, je voudrais réserver une table pour ce soir.", among: ["en", "fr"]).language == "fr", "French text")
    let english = TextLanguage.identify("Please send the quarterly report before Thursday.", among: ["en"])
    check(english.language == "en" && english.confidence > 0.5, "English text with English selected")
    let mismatch = TextLanguage.identify("Ich möchte heute Abend einen Tisch reservieren, bitte.", among: ["en"])
    check(mismatch.confidence < 0.5, "German speech with only English selected is low confidence (\(mismatch.confidence))")
    check(TextLanguage.identify("Hi.", among: ["de"]) == ("de", 1), "too little text is not judged")
}

private func speechGuards() {
    check(TranscriptGuard.isRepetitive("thank you thank you thank you so much"), "a phrase three times loops")
    check(!TranscriptGuard.isRepetitive("no, no, no, that's not it at all"), "a word three times is speech")
    check(TranscriptGuard.isRepetitive("the the the the the end of it"), "a word five times loops")
    check(!TranscriptGuard.isRepetitive("We ship on Thursday and review on Friday."), "normal speech")
    check(TranscriptGuard.isTooFast("This is a perfectly ordinary sentence that goes on.", speechSeconds: 0.5), "50 characters in half a second")
    check(!TranscriptGuard.isTooFast("This is a perfectly ordinary sentence.", speechSeconds: 3), "ordinary pace")
    check(TranscriptGuard.isPhantom("Thank you.") && TranscriptGuard.isPhantom(" Thanks for watching! ") && !TranscriptGuard.isPhantom("Thank you, Priya."),
          "phantom outputs")
    check(TranscriptGuard.accept("Thank you.", speechSeconds: 1, quiet: true).isEmpty, "a phantom over quiet audio is dropped")
    check(TranscriptGuard.accept("Thank you.", speechSeconds: 1, quiet: false) == "Thank you.", "but kept when someone clearly said it")
    check(TranscriptGuard.accept("[BLANK_AUDIO] Hello there (music)", speechSeconds: 2, quiet: false) == "Hello there", "non-speech tags removed")
    check(WhisperPrompt.make(vocabulary: [], previousText: nil) == nil, "no prompt without vocabulary or context")
    check(WhisperPrompt.make(vocabulary: ["Anaïs", "Kubernetes", "anaïs", " "], previousText: nil) == "Vocabulary: Anaïs, Kubernetes.",
          "vocabulary sentence, de-duplicated")
    let many = WhisperPrompt.make(vocabulary: (0..<200).map { "Term\($0)" }, previousText: String(repeating: "word ", count: 400)) ?? ""
    check(many.count <= WhisperPrompt.maximumCharacters && many.contains("Term0") && !many.contains("Term60") && many.hasSuffix("word"),
          "capped at 50 terms and the prompt budget, ending with the previous text (\(many.count) chars)")
}

private func speechSegmentation() {
    let window = 512
    func probs(_ pattern: [(Float, TimeInterval)]) -> [Float] {
        pattern.flatMap { [Float](repeating: $0.0, count: Int($0.1 * 16_000) / window) }
    }
    // 0.5 s silence, 1 s speech, 0.5 s pause, a 96 ms click, 0.5 s pause, 1 s speech with a 0.2 s dip, 0.5 s silence.
    let p = probs([(0, 0.5), (0.9, 1), (0.1, 0.5), (0.9, 0.096), (0.1, 0.5), (0.9, 0.5), (0.2, 0.2), (0.9, 0.5), (0, 0.5)])
    let regions = SpeechRegions.regions(probabilities: p, window: window, totalSamples: p.count * window)
    check(regions.count == 2, "two speech regions; the click is too short (\(regions))")
    if regions.count == 2 {
        check(abs(Double(regions[0].lowerBound) / 16_000 - 0.4) < 0.04 && abs(Double(regions[0].upperBound) / 16_000 - 1.6) < 0.04,
              "padded by 100 ms on both sides (\(regions[0]))")
        check(Double(regions[1].count) / 16_000 > 1.2, "a 200 ms dip does not split a phrase")
    }
    // Streaming: regions close as the pauses arrive, and the open one is visible meanwhile.
    var segmenter = StreamingSegmenter(window: window, parameters: .dictation)
    let first = segmenter.push(probs([(0.9, 1)]))
    check(first.isEmpty && segmenter.open != nil, "still speaking: nothing closed, one open region")
    let closed = segmenter.push(probs([(0, 0.4)]))
    check(closed.count == 1 && segmenter.open == nil, "a 300 ms pause closes it")
    // A monologue without pauses is cut at 15 s.
    var long = StreamingSegmenter(window: window, parameters: .dictation)
    let cut = long.push(probs([(0.9, 20)]))
    let tail = long.finish(totalSamples: 20 * 16_000)
    check(cut.count == 1 && abs(Double(cut[0].count) / 16_000 - 15.1) < 0.1 && tail != nil && tail!.lowerBound == cut[0].upperBound,
          "forced split at 15 s, contiguous with the rest")
    // Energy gate: tone bursts in digital silence.
    var samples = [Float](repeating: 0, count: 16_000)
    for i in 0..<16_000 { samples.append(0.3 * Float(sin(2 * Double.pi * 220 * Double(i) / 16_000))) }
    samples += [Float](repeating: 0, count: 16_000)
    let energy = EnergyVAD()
    let found = SpeechRegions.regions(probabilities: energy.probabilities(samples, continuing: false), window: energy.window,
                                      totalSamples: samples.count)
    check(found.count == 1 && abs(Double(found[0].lowerBound) / 16_000 - 0.9) < 0.1 && abs(Double(found[0].upperBound) / 16_000 - 2.1) < 0.1,
          "the energy gate finds the burst (\(found))")
    check(SpeechRegions.regions(probabilities: energy.probabilities([Float](repeating: 0, count: 32_000), continuing: false),
                                window: energy.window, totalSamples: 32_000).isEmpty, "silence is silence")
}

@MainActor private func speechPriorityGate() {
    let gate = PriorityGate()
    var order: [String] = []
    _ = complete(5) {
        await gate.acquire(.meeting)          // held by a running meeting job
        let meeting = Task { @MainActor in await gate.acquire(.meeting); order.append("meeting"); gate.release() }
        await Task.yield()
        let dictation = Task { @MainActor in await gate.acquire(.dictation); order.append("dictation"); gate.release() }
        await Task.yield()
        gate.release()
        await meeting.value
        await dictation.value
    }
    check(order == ["dictation", "meeting"], "a dictation job goes before a queued meeting job (\(order))")
}

private func speechModelLayout() {
    let root = URL(fileURLWithPath: "/tmp/models-root")
    let file = ModelLayout(ModelCatalog.whisperBase, root: root)
    check(!file.isFolder && file.final.path == "/tmp/models-root/asr/ggml-base-q5_1.bin" && file.partial.lastPathComponent == "ggml-base-q5_1.bin.partial",
          "single files live in Models/<kind>/<file> with a .partial beside them")
    let parakeet = ModelLayout(ModelCatalog.parakeetV3, root: root)
    check(parakeet.isFolder && parakeet.final.path == "/tmp/models-root/asr/parakeet-tdt-0.6b-v3",
          "Core ML sets are folders named by id")
    check(parakeet.requiredEntries == ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc",
                                       "parakeet_vocab.json"], "Parakeet needs exactly what FluidAudio loads (\(parakeet.requiredEntries.sorted()))")
    check(ModelLayout(ModelCatalog.diarization, root: root).requiredEntries.contains("plda-parameters.json"), "diarization includes the PLDA file")
    check(ModelLayout(ModelCatalog.localVQE, root: root).requiredEntries == ["localvqe-v1.3-4.8M-16ms.mlmodelc"], "LocalVQE v1.3, 16 ms")
    check(!file.isInstalled() && !parakeet.isInstalled(), "nothing installed in an empty root")
}

private func speechGate() {
    let fine = DownloadConditions(networkUsable: true, lowPowerMode: false, freeBytes: 50 << 30)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func gate(enabled: Bool = true, busy: Bool = false, _ c: DownloadConditions = fine, retry: TimeInterval = 0) -> AutoDownloadStatus? {
        AutoDownloadGate.blocker(enabled: enabled, busy: busy, conditions: c, diskRetryAfter: retry, now: now)
    }
    var c = fine
    check(gate() == nil, "all clear")
    check(gate(enabled: false) == .disabled, "the setting turns it off")
    c.networkUsable = false
    check(gate(c) == .waitingForNetwork, "no usable network (offline, hotspot or Low Data Mode)")
    c = fine; c.lowPowerMode = true
    check(gate(c) == .waitingForPower, "Low Power Mode pauses")
    c = fine; c.freeBytes = 9 << 30
    check(gate(c) == .waitingForDisk(freeBytes: 9 << 30), "under 10 GB free")
    check(gate(retry: now.timeIntervalSince1970 + 3600) == .waitingForDisk(freeBytes: 50 << 30), "the disk retry waits for its day")
    check(gate(busy: true) == .waitingWhileBusy, "yields while dictating or in a meeting")
}

// MARK: - Downloads

@MainActor private func speechDownloads() {
    // Resume after a dropped connection, with the hash covering bytes from both attempts.
    let data = pattern(300_000, seed: 7)
    let model = testModel("resume-model", data: data)
    let corruptData = pattern(50_000, seed: 9)
    let corrupt = testModel("corrupt-model", data: corruptData, sha: pattern(50_000, seed: 10).sha256)
    let missing = testModel("missing-model", data: Data([1, 2, 3]))
    var huge = testModel("huge-model", data: Data([1, 2, 3]))
    huge.bytes = 1 << 52
    MockModelServer.serve(model.url!.absoluteString, .init(data: data, failAfter: 120_000))
    MockModelServer.serve(corrupt.url!.absoluteString, .init(data: corruptData))
    MockModelServer.serve(huge.url!.absoluteString, .init(data: Data([1, 2, 3])))
    let (manager, root) = testManager([model, corrupt, missing, huge])
    var changes: [String] = []
    let subscription = manager.changes.sink { changes.append($0) }

    let result = drain(manager.download(model.id))
    check(result.error == nil, "the download completes after a dropped connection (\(String(describing: result.error)))")
    check(manager.state(of: model.id) == .installed, "installed")
    check((try? Data(contentsOf: root.appendingPathComponent("llm/resume-model.bin"))) == data, "the file is byte-identical")
    check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("llm/resume-model.bin.partial").path), "no partial left")
    let ranges = MockModelServer.ranges(for: model.url!.absoluteString)
    check(ranges.count == 2 && ranges[0] == nil && (ranges[1]?.hasPrefix("bytes=") ?? false) && ranges[1] != "bytes=0-",
          "the retry asked for the rest with a Range header (\(ranges))")
    check(result.updates.last.map { $0.bytesReceived == $0.bytesExpected } ?? false, "progress ends at 100 %")
    check(changes.contains(model.id), "state changes are published")
    check(manager.location(of: model.id) == root.appendingPathComponent("llm/resume-model.bin"), "location of an installed file")
    check(drain(manager.download(model.id)).error == nil && MockModelServer.ranges(for: model.url!.absoluteString).count == 2,
          "downloading an installed model is a no-op")

    let damaged = drain(manager.download(corrupt.id))
    check((damaged.error as? ModelError) == .checksumMismatch, "a hash mismatch fails the download")
    check(manager.state(of: corrupt.id) == .damaged && manager.location(of: corrupt.id) == nil, "and marks the model damaged")
    check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("llm/corrupt-model.bin.partial").path), "the bad bytes are deleted")

    check((drain(manager.download(missing.id)).error as? ModelError) == .http(404), "HTTP errors surface")
    if case .notEnoughSpace? = drain(manager.download(huge.id)).error as? ModelError {} else { check(false, "the free-space pre-flight refuses") }
    check((drain(manager.download("not-in-catalog")).error as? ModelError) == .unknownModel("not-in-catalog"), "unknown ids")
    check(manager.diskUsage >= Int64(data.count), "disk usage counts installed models (\(manager.diskUsage))")
    subscription.cancel()
}

@MainActor private func speechPauseResume() {
    let data = pattern(400_000, seed: 3)
    let model = testModel("slow-model", data: data)
    MockModelServer.serve(model.url!.absoluteString, .init(data: data, chunk: 16 << 10, delay: 0.02))
    let (manager, _) = testManager([model])
    let stream = manager.download(model.id)
    check(waitUntil { if case .downloading(let f) = manager.state(of: model.id) { return f > 0.1 } else { return false } },
          "the download makes progress")
    check(manager.readiness(of: model.id).map { $0 > 0 && $0 < 1 } ?? false, "readiness reports the fraction while downloading")
    manager.pause(model.id)
    check((drain(stream).error as? ModelError) == .cancelled, "pausing ends the stream with “Download paused.”")
    check(waitUntil { if case .paused(let f) = manager.state(of: model.id) { return f > 0 && f < 1 } else { return false } },
          "paused with a partial (\(manager.state(of: model.id)))")
    MockModelServer.serve(model.url!.absoluteString, .init(data: data))
    check(drain(manager.download(model.id)).error == nil && manager.state(of: model.id) == .installed, "resuming finishes it")
    let ranges = MockModelServer.ranges(for: model.url!.absoluteString).compactMap { $0 }
    check(!ranges.isEmpty, "the resume used a Range request (\(ranges))")
    check(manager.readiness(of: model.id) == nil, "no readiness once installed")
}

@MainActor private func speechFolderDownload() {
    // A FluidAudio-style repository behind a mirror, listed over two API pages, with an extra file that must be skipped.
    Defaults[.modelMirrorURL] = "https://mirror.test/"
    defer { Defaults.reset(.modelMirrorURL) }
    let model = ModelDescriptor(id: "test-diarization", kind: .diarization, name: "Test diarization", engine: "fluidaudio", bytes: 10_000,
                                repository: "acme/diar-coreml", revision: "main", licence: "CC-BY-4.0")
    let base = "https://mirror.test/acme/diar-coreml/resolve/main/"
    var entries: [[String: Any]] = []
    var expected: [String: Data] = [:]
    for (i, bundle) in ["Segmentation", "FBank", "Embedding", "PldaRho"].enumerated() {
        let mil = pattern(900 + i, seed: UInt8(i)), weights = pattern(20_000 + i, seed: UInt8(40 + i))
        expected["\(bundle).mlmodelc/model.mil"] = mil
        expected["\(bundle).mlmodelc/weights/weight.bin"] = weights
        entries.append(["type": "directory", "path": "\(bundle).mlmodelc"])
        entries.append(["type": "file", "path": "\(bundle).mlmodelc/model.mil", "size": mil.count, "oid": mil.gitBlobSHA1])
        entries.append(["type": "file", "path": "\(bundle).mlmodelc/weights/weight.bin", "size": weights.count, "oid": "pointer",
                        "lfs": ["oid": weights.sha256, "size": weights.count]])
    }
    let plda = Data(#"{"tensors":{}}"#.utf8)
    expected["plda-parameters.json"] = plda
    entries.append(["type": "file", "path": "plda-parameters.json", "size": plda.count, "oid": plda.gitBlobSHA1])
    entries.append(["type": "file", "path": "README.md", "size": 5, "oid": Data("hello".utf8).gitBlobSHA1])
    for (path, data) in expected { MockModelServer.serve(base + path, .init(data: data)) }
    let api = "https://mirror.test/api/models/acme/diar-coreml/tree/main?recursive=true"
    let page2 = api + "&cursor=2"
    let half = entries.count / 2
    MockModelServer.serve(api, .init(data: try! JSONSerialization.data(withJSONObject: Array(entries[..<half])),
                                     headers: ["Link": "<\(page2)>; rel=\"next\""]))
    MockModelServer.serve(page2, .init(data: try! JSONSerialization.data(withJSONObject: Array(entries[half...]))))
    // One weight file drops mid-way once.
    MockModelServer.serve(base + "Embedding.mlmodelc/weights/weight.bin",
                          .init(data: expected["Embedding.mlmodelc/weights/weight.bin"]!, failAfter: 5_000))

    let (manager, root) = testManager([model])
    let result = drain(manager.download(model.id))
    check(result.error == nil, "the folder set downloads through the mirror (\(String(describing: result.error)))")
    let folder = root.appendingPathComponent("diarization/test-diarization")
    check(manager.state(of: model.id) == .installed && manager.location(of: model.id) == folder, "installed as a folder")
    check(expected.allSatisfy { (try? Data(contentsOf: folder.appendingPathComponent($0.key))) == $0.value }, "every file is byte-identical")
    check(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("README.md").path), "files FluidAudio does not load are skipped")
    check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("diarization/test-diarization.partial").path),
          "the staging folder was renamed into place")
    check(MockModelServer.ranges(for: page2).count == 1, "the second listing page was followed")
    check(MockModelServer.ranges(for: base + "Embedding.mlmodelc/weights/weight.bin").last == "bytes=5000-", "a dropped file resumed where it stopped")
}

@MainActor private func speechAutomaticQueue() {
    let slowData = pattern(300_000, seed: 21), fastData = pattern(20_000, seed: 22), lateData = pattern(30_000, seed: 23)
    let slow = testModel("auto-slow", data: slowData), fast = testModel("auto-fast", data: fastData), late = testModel("auto-late", data: lateData)
    MockModelServer.serve(slow.url!.absoluteString, .init(data: slowData, chunk: 16 << 10, delay: 0.03))
    MockModelServer.serve(fast.url!.absoluteString, .init(data: fastData))
    MockModelServer.serve(late.url!.absoluteString, .init(data: lateData))
    let environment = FakeEnvironment()
    let (manager, _) = testManager([slow, fast, late], plan: [slow, fast], environment: environment)

    check(manager.autoDownloadStatus == .idle && manager.readiness(of: slow.id) == nil, "idle until started")
    manager.startAutomaticDownloads()
    check(waitUntil { if case .downloading(let id, _) = manager.autoDownloadStatus { return id == slow.id } else { return false } },
          "the plan starts in order (\(manager.autoDownloadStatus))")
    check(manager.readiness(of: fast.id) == 0, "a queued model reports 0 % readiness")
    check(manager.readiness(of: late.id) == nil, "a model outside the plan has no readiness")

    // Busy: the automatic transfer yields and resumes afterwards.
    _ = waitUntil { if case .downloading(let f) = manager.state(of: slow.id) { return f > 0.05 } else { return false } }
    manager.setUserBusy(true)
    check(waitUntil { manager.autoDownloadStatus == .waitingWhileBusy }, "yields while busy (\(manager.autoDownloadStatus))")
    check(waitUntil { if case .paused = manager.state(of: slow.id) { return true } else { return false } }, "the partial is kept")

    // An explicit download jumps the queue even while busy.
    check(drain(manager.download(late.id)).error == nil && manager.state(of: late.id) == .installed, "explicit downloads run while busy")
    check(manager.state(of: slow.id) != .installed, "the automatic one is still waiting")
    manager.setUserBusy(false)
    check(waitUntil(30) { manager.autoDownloadStatus == .upToDate }, "the queue resumes and finishes (\(manager.autoDownloadStatus))")
    check(manager.state(of: slow.id) == .installed && manager.state(of: fast.id) == .installed, "both automatic models installed")
    check(MockModelServer.ranges(for: slow.url!.absoluteString).contains { $0 != nil }, "the yielded transfer resumed with a Range request")

    // Deleting keeps the queue from bringing it back; downloading it again clears that.
    check((try? manager.delete(fast.id)) != nil && manager.state(of: fast.id) == .notDownloaded, "delete")
    manager.startAutomaticDownloads()
    check(waitUntil { manager.autoDownloadStatus == .upToDate } && manager.state(of: fast.id) == .notDownloaded,
          "a deleted model is not re-downloaded automatically")
    check(drain(manager.download(fast.id)).error == nil && manager.state(of: fast.id) == .installed, "but can be downloaded again")

    // The guards, as the status Settings shows.
    let pending = testModel("auto-pending", data: fastData)
    MockModelServer.serve(pending.url!.absoluteString, .init(data: fastData))
    let gated = FakeEnvironment(networkUsable: false)
    let (queue, _) = testManager([pending], plan: [pending], environment: gated)
    queue.startAutomaticDownloads()
    check(queue.autoDownloadStatus == .waitingForNetwork, "waits for a usable network")
    gated.set { $0.networkUsable = true; $0.lowPowerMode = true }
    check(queue.autoDownloadStatus == .waitingForPower, "then for Low Power Mode to end")
    gated.set { $0.lowPowerMode = false; $0.freeBytes = 2 << 30 }
    check(queue.autoDownloadStatus == .waitingForDisk(freeBytes: 2 << 30), "then for disk space")
    let retry = Defaults[.autoDownloadDiskRetryAfter] - Date().timeIntervalSince1970
    check(abs(retry - AutoDownloadPolicy.diskRetryInterval) < 60, "and schedules the daily disk retry (\(retry) s)")
    Defaults.reset(.autoDownloadDiskRetryAfter)
    Defaults[.autoDownloadModels] = false
    gated.set { $0.freeBytes = 100 << 30 }
    check(queue.autoDownloadStatus == .disabled, "the setting turns the queue off")
    Defaults.reset(.autoDownloadModels)
    check(waitUntil { queue.autoDownloadStatus == .upToDate } && queue.state(of: pending.id) == .installed, "and back on, it runs")
}

@MainActor private func speechImportDelete() {
    let data = pattern(10_000, seed: 51)
    let model = testModel("import-model", data: data)
    let (manager, root) = testManager([model, ModelCatalog.diarization])
    let source = SuperFlowPaths.support.appendingPathComponent("import-source.bin")
    try? data.write(to: source)
    let wrong = SuperFlowPaths.support.appendingPathComponent("import-wrong.bin")
    try? pattern(10_000, seed: 52).write(to: wrong)
    if case .failure(let error)? = complete(60, { try await manager.importModel(model.id, from: wrong) }) {
        check((error as? ModelError) == .checksumMismatch, "a file with the wrong hash is refused")
    } else { check(false, "importing a wrong file must fail") }
    check(manager.state(of: model.id) == .notDownloaded, "nothing installed from a bad file")
    if case .success? = complete(60, { try await manager.importModel(model.id, from: source) }) {} else { check(false, "import a verified file") }
    check(manager.state(of: model.id) == .installed && (try? Data(contentsOf: manager.location(of: model.id)!)) == data, "imported")
    check(FileManager.default.fileExists(atPath: source.path), "the user's file stays where it was")

    // A folder set imports when it holds every required entry.
    let folder = SuperFlowPaths.support.appendingPathComponent("import-diarization", isDirectory: true)
    for entry in ModelLayout(ModelCatalog.diarization, root: root).requiredEntries {
        let url = folder.appendingPathComponent(entry)
        if entry.hasSuffix(".mlmodelc") { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        else { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); try? Data("{}".utf8).write(to: url) }
    }
    if case .success? = complete(60, { try await manager.importModel(ModelCatalog.diarization.id, from: folder) }) {} else { check(false, "folder import") }
    check(manager.state(of: ModelCatalog.diarization.id) == .installed, "folder set imported")
    check((try? manager.delete(model.id)) != nil && manager.state(of: model.id) == .notDownloaded && manager.location(of: model.id) == nil,
          "delete removes the file")
    check((try? manager.delete("nope")) == nil, "deleting an unknown id throws")
}

// MARK: - Real models (dev folders only)

var devFolders: [URL] {
    (ProcessInfo.processInfo.environment["SUPERFLOW_DEV_MODELS"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
}

func devModel(_ names: String...) -> URL? {
    for folder in devFolders {
        for name in names where FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            return folder.appendingPathComponent(name)
        }
    }
    return nil
}

/// A Models folder that links whatever dev models exist, and a manager over it (no network, nothing queued).
@MainActor func devManager() -> ModelManager? {
    let links: [(ModelDescriptor, URL?)] = [
        (ModelCatalog.parakeetV3, devModel("parakeet-tdt-0.6b-v3")),
        (ModelCatalog.whisperBase, devModel(ModelCatalog.whisperBase.fileName)),
        (ModelCatalog.sileroVAD, devModel(ModelCatalog.sileroVAD.fileName)),
        (ModelCatalog.diarization, devModel("speaker-diarization", ModelCatalog.diarization.id)),
        (ModelCatalog.qwen35_4B, devModel(ModelCatalog.qwen35_4B.fileName)),
        (ModelCatalog.qwen35_2B, devModel(ModelCatalog.qwen35_2B.fileName)),
    ]
    guard links.contains(where: { $0.1 != nil }) else { return nil }
    let root = SuperFlowPaths.support.appendingPathComponent("dev-models-\(UUID().uuidString)", isDirectory: true)
    for case let (model, source?) in links {
        let layout = ModelLayout(model, root: root)
        try? FileManager.default.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: layout.final, withDestinationURL: source)
    }
    return ModelManager(catalog: ModelCatalog.all, root: { root }, environment: FakeEnvironment(networkUsable: false), plan: { [] })
}

/// Speech synthesised to a 16 kHz WAV with `say -o` (written to a file, never played), with silence around it.
func spoken(_ text: String, voice: String, padding: TimeInterval = 0.5) -> [Float]? {
    let url = SuperFlowPaths.support.appendingPathComponent("say-\(UUID().uuidString).wav")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-v", voice, "-o", url.path, "--file-format=WAVE", "--data-format=LEI16@16000", text]
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    guard process.terminationStatus == 0, let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate == 16_000,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0] else { return nil }
    let silence = [Float](repeating: 0, count: Int(padding * 16_000))
    return silence + Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))) + silence
}

private func words(_ text: String) -> String { text.lowercased().components(separatedBy: CharacterSet.letters.inverted).joined(separator: " ") }

@MainActor private func speechSilero() {
    guard let manager = devManager(), manager.location(of: ModelCatalog.sileroVAD.id) != nil,
          let speech = spoken("The quick brown fox jumps over the lazy dog.", voice: "Samantha", padding: 1) else {
        print("  (skipped: no Silero VAD in the dev model folders, or no speech synthesiser)"); return
    }
    let service = SpeechService(models: manager)
    let regions: [Range<Int>] = { if case .success(let r)? = complete(60, { await service.speechSegments(in: AudioClip(samples: speech)) }) { return r }; return [] }()
    let covered = regions.reduce(0) { $0 + $1.count }
    let spoken = speech.count - 32_000
    check(!regions.isEmpty && (regions.first?.lowerBound ?? 0) > 8_000 && (regions.last?.upperBound ?? .max) < speech.count - 8_000,
          "Silero finds the speech and not the silence around it (\(regions))")
    check(Double(covered) > 0.7 * Double(spoken), "and covers most of it (\(covered) of \(spoken))")
    let quiet: [Range<Int>] = { if case .success(let r)? = complete(60, { await service.speechSegments(in: AudioClip(samples: [Float](repeating: 0, count: 48_000))) }) { return r }; return [] }()
    check(quiet.isEmpty, "no speech in silence")
}

@MainActor private func speechParakeet() {
    guard Machine.isAppleSilicon, let manager = devManager(), manager.state(of: ModelCatalog.parakeetV3.id) == .installed else {
        print("  (skipped: no Parakeet v3 folder in the dev model folders)"); return
    }
    guard let short = spoken("Please send the quarterly report to Priya by Thursday afternoon.", voice: "Samantha"),
          let a = spoken("First, we review the design for the new onboarding screens.", voice: "Samantha", padding: 0.4),
          let b = spoken("Second, the release moves to the end of the month.", voice: "Samantha", padding: 0.4),
          let c = spoken("Finally, everyone sends their notes by Friday.", voice: "Samantha", padding: 0.4),
          let french = spoken("Bonjour, je voudrais réserver une table pour quatre personnes ce soir.", voice: "Thomas") else {
        print("  (skipped: no speech synthesiser)"); return
    }
    let service = SpeechService(models: manager)
    let started = Date()
    guard case .success? = complete(600, { try await service.prepare(modelID: ModelCatalog.parakeetV3.id) }) else {
        check(false, "Parakeet prepares from the Models folder"); return
    }
    print("  parakeet: prepared (load + warm) in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
    check(service.activeEngineID == ModelCatalog.parakeetV3.id && service.availableEngines.contains(ModelCatalog.parakeetV3.id), "active engine")

    let english = TranscriptionOptions(languages: ["en"], vocabulary: ["Priya"])
    var latencies: [TimeInterval] = []
    var text = ""
    for _ in 0..<3 {
        let t0 = Date()
        if case .success(let transcript)? = complete(60, { try await service.transcribe(AudioClip(samples: short), options: english, priority: .dictation) }) {
            latencies.append(Date().timeIntervalSince(t0))
            text = transcript.text
            check(transcript.language == "en" && transcript.languageConfidence > 0.5, "English, confidently (\(transcript.languageConfidence))")
        }
    }
    let heard = words(text)
    check(heard.contains("quarterly report") && heard.contains("thursday"), "the dictation is recognised: '\(text)'")
    let audioSeconds = Double(short.count) / 16_000
    let warm = latencies.dropFirst().min() ?? .infinity
    print("  parakeet: \(String(format: "%.1f", audioSeconds)) s of audio in \(String(format: "%.3f", warm)) s warm (target ≈ 0.16 s for 4 s on M4 Pro)")
    check(warm < 1.5, "warm transcription well under real time (\(warm) s)")

    // Silence is "nothing heard", never a phantom sentence.
    if case .failure(let error)? = complete(60, { try await service.transcribe(AudioClip(samples: [Float](repeating: 0, count: 32_000)), options: english, priority: .dictation) }) {
        check((error as? SpeechError) == .noSpeech, "silence throws noSpeech")
    } else { check(false, "silence must not produce text") }

    // French audio while only English is selected: Parakeet writes French and flags the language.
    if case .success(let transcript)? = complete(60, { try await service.transcribe(AudioClip(samples: french), options: english, priority: .dictation) }) {
        check(transcript.languageConfidence < 0.5, "“Speaking a different language?” confidence is low (\(transcript.languageConfidence)): '\(transcript.text)'")
    } else { check(false, "French clip transcribes") }
    if case .success(let transcript)? = complete(60, { try await service.transcribe(AudioClip(samples: french), options: TranscriptionOptions(languages: ["fr"]), priority: .dictation) }) {
        check(transcript.language == "fr" && words(transcript.text).contains("table"), "French with French selected: '\(transcript.text)'")
    }

    // Incremental: 40 ms clips as the microphone would deliver them; pauses close segments while "the key is held".
    let utterance = a + b + c
    let clips = AsyncStream<AudioClip> { continuation in
        var offset = 0
        while offset < utterance.count {
            let end = min(utterance.count, offset + 640)
            continuation.yield(AudioClip(samples: Array(utterance[offset..<end]), startTime: 100 + Double(offset) / 16_000))
            offset = end
        }
        continuation.finish()
    }
    var events: [TranscriptionEvent] = []
    let streamed = complete(120) {
        for try await event in service.transcribeIncrementally(clips, options: english, priority: .dictation) { events.append(event) }
    }
    check({ if case .success? = streamed { return true }; return false }(), "the stream finishes (\(String(describing: streamed)))")
    let segments = events.compactMap { if case .segment(let s) = $0 { return s }; return nil }
    let partials = events.compactMap { if case .partial(let p) = $0 { return p }; return nil }
    let final = events.compactMap { if case .final(let t) = $0 { return t }; return nil }.first
    check(segments.count >= 3, "each sentence closes as its own segment (\(segments.count))")
    check(!partials.isEmpty, "partials arrive while speaking (\(partials.count))")
    check(zip(segments.dropFirst(), segments).allSatisfy { $0.start >= $1.end - 0.001 } && (segments.first?.start ?? 0) >= 100,
          "segments are ordered, in the clips' time base")
    let all = words(final?.text ?? "")
    check(all.contains("onboarding") && all.contains("release") && all.contains("friday"), "the final text has all three sentences: '\(final?.text ?? "")'")
    check(final?.segments.count == segments.count, "the final carries the segments")
    service.unload()
    check(service.activeEngineID == nil, "unload")
}

@MainActor private func speechWhisper() {
    guard let manager = devManager(), manager.state(of: ModelCatalog.whisperBase.id) == .installed else {
        print("  (skipped: no Whisper model in the dev model folders)"); return
    }
    guard let english = spoken("Please send the quarterly report by Thursday afternoon.", voice: "Samantha"),
          let french = spoken("Bonjour, je voudrais réserver une table pour ce soir.", voice: "Thomas") else {
        print("  (skipped: no speech synthesiser)"); return
    }
    let service = SpeechService(models: manager)
    guard case .success? = complete(300, { try await service.prepare(modelID: ModelCatalog.whisperBase.id) }) else {
        check(false, "Whisper prepares"); return
    }
    let t0 = Date()
    if case .success(let transcript)? = complete(120, { try await service.transcribe(AudioClip(samples: english), options: TranscriptionOptions(languages: ["en"], vocabulary: ["Priya", "Kubernetes"]), priority: .dictation) }) {
        print("  whisper base: \(String(format: "%.1f", Double(english.count) / 16_000)) s in \(String(format: "%.3f", Date().timeIntervalSince(t0))) s")
        check(words(transcript.text).contains("quarterly report"), "English with a forced language and a vocabulary prompt: '\(transcript.text)'")
    } else { check(false, "Whisper transcribes English") }
    if case .success(let transcript)? = complete(120, { try await service.transcribe(AudioClip(samples: french), options: TranscriptionOptions(languages: ["en", "fr"]), priority: .dictation) }) {
        check(transcript.language == "fr" && transcript.languageConfidence > 0.5, "detects French among the selected languages (\(transcript.language), \(transcript.languageConfidence))")
        check(words(transcript.text).contains("table"), "and transcribes it: '\(transcript.text)'")
    } else { check(false, "Whisper transcribes French") }
    if case .success(let transcript)? = complete(120, { try await service.transcribe(AudioClip(samples: french), options: TranscriptionOptions(languages: []), priority: .dictation) }) {
        check(transcript.language == "fr", "auto-detect among all languages (\(transcript.language))")
    }
    service.unload()
}

@MainActor private func speechDiarization() {
    guard Machine.isAppleSilicon, let manager = devManager(), manager.state(of: ModelCatalog.diarization.id) == .installed else {
        print("  (skipped: no diarization set in the dev model folders)"); return
    }
    let lines = [("Samantha", "Thanks for joining. Let's start with the roadmap for next quarter and the hiring plan."),
                 ("Daniel", "Sounds good. I think we should ship the beta first, then talk about hiring in March."),
                 ("Samantha", "Agreed. Can you send me the updated timeline and the budget by Friday?"),
                 ("Daniel", "Yes, I will send both on Thursday so we have time to review them together.")]
    var audio: [Float] = []
    for (voice, line) in lines {
        guard let clip = spoken(line, voice: voice, padding: 0.3) else { print("  (skipped: no speech synthesiser)"); return }
        audio += clip
    }
    let service = SpeechService(models: manager)
    let t0 = Date()
    switch complete(600, { try await service.diarize(AudioClip(samples: audio)) }) {
    case .success(let segments)?:
        let speakers = Set(segments.compactMap(\.speakerID))
        print("  diarization: \(String(format: "%.1f", Double(audio.count) / 16_000)) s, \(segments.count) turns, \(speakers.count) speakers in \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        check(speakers.count >= 2, "two voices are two speakers")
        check(segments.allSatisfy { $0.end > $0.start && $0.channel == .system }, "turns are well-formed")
    case .failure(let error)?: check(false, "diarization failed: \(error.localizedDescription)")
    case nil: check(false, "diarization timed out")
    }
}

/// Two installed speech models, the preferred one damaged: the next one is tried instead of every dictation failing on
/// the first; the first error is reported only when none loads.
@MainActor private func speechBrokenModelFallsBack() {
    final class Installed: ModelManaging {
        let files: [String: URL]
        var asked: [String] = []
        init(_ files: [String: URL]) { self.files = files }
        var catalog: [ModelDescriptor] { ModelCatalog.all }
        func state(of id: String) -> ModelState { files[id] == nil ? .notDownloaded : .installed }
        func location(of id: String) -> URL? { asked.append(id); return files[id] }
        func download(_ id: String) -> AsyncThrowingStream<DownloadProgress, Error> { AsyncThrowingStream { $0.finish() } }
        func pause(_ id: String) {}
        func delete(_ id: String) throws {}
        func importModel(_ id: String, from file: URL) async throws {}
        var diskUsage: Int64 { 0 }
        var changes: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
        func startAutomaticDownloads() {}
        var autoDownloadStatus: AutoDownloadStatus { .upToDate }
        func setUserBusy(_ busy: Bool) {}
        func readiness(of id: String) -> Double? { nil }
    }
    let folder = SuperFlowPaths.ensure(SuperFlowPaths.support.appendingPathComponent("broken-models-\(UUID().uuidString)", isDirectory: true))
    let small = folder.appendingPathComponent("small.bin"), base = folder.appendingPathComponent("base.bin")
    try? Data("damaged".utf8).write(to: small)
    try? Data("damaged".utf8).write(to: base)
    let models = Installed([ModelCatalog.whisperSmall.id: small, ModelCatalog.whisperBase.id: base])
    Defaults[.asrModelID] = ModelCatalog.whisperSmall.id
    defer { Defaults.reset(.asrModelID) }
    let service = SpeechService(models: models)
    let silence = [Float](repeating: 0, count: 8_000)
    let tone: [Float] = silence + (0..<24_000).map { (i: Int) -> Float in Float(0.3 * sin(Double(i) * 2 * Double.pi * 220 / 16_000)) } + silence
    let result = complete(60) { try await service.transcribe(AudioClip(samples: tone), options: TranscriptionOptions(languages: ["en"]), priority: .dictation) }
    check(models.asked.contains(ModelCatalog.whisperSmall.id) && models.asked.contains(ModelCatalog.whisperBase.id),
          "the damaged preferred model is followed by the other installed one: \(models.asked)")
    if case .failure(let error)? = result {
        check(error is SpeechError && error.localizedDescription.contains("small.bin"), "with none loadable, the preferred model's error: \(error.localizedDescription)")
    } else { check(false, "two damaged models can't transcribe") }
}

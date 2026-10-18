import Combine
import Foundation
import SuperFlowCore

extension Defaults.Keys {
    /// Models the user deleted: the automatic queue leaves them alone until the user downloads them again.
    static let speechKitRemovedModels = Key<[String]>("speechKit.removedModels", default: [])
}

/// The model store (local-models.md §5): catalog state, downloads with resume and verification, import, delete, and
/// the automatic background queue that follows `AutoDownloadPolicy` (owner decision: no prompt, no setup step).
///
/// One transfer runs at a time. Explicit downloads go first and pre-empt an automatic transfer, which resumes from its
/// partial afterwards. Automatic transfers use a session that refuses expensive and constrained paths and yield while
/// the user dictates or records a meeting.
@MainActor
public final class ModelManager: ModelManaging {
    public static let shared = ModelManager()

    public let catalog: [ModelDescriptor]
    private let root: () -> URL
    private let environment: DownloadEnvironment
    private let plan: () -> [ModelDescriptor]
    private let retryDelays: [TimeInterval]
    private let sessionConfiguration: (_ automatic: Bool) -> URLSessionConfiguration
    private let changeSubject = PassthroughSubject<String, Never>()

    private struct Transfer {
        let id: String
        var explicit: Bool
        let task: Task<Void, Never>
    }

    private var transfer: Transfer?
    private var explicitQueue: [String] = []
    private var listeners: [String: [AsyncThrowingStream<DownloadProgress, Error>.Continuation]] = [:]
    private var progress: [String: DownloadProgress] = [:]
    private var rateSamples: [(time: Date, bytes: Int64)] = []
    private var lastNotified: [String: Date] = [:]
    private var damaged: Set<String> = []
    private var pausedByUser: Set<String> = []
    private var pendingDeletion: Set<String> = []
    /// Automatic attempts that failed for a reason a retry will not fix (hash mismatch, HTTP 4xx) this session.
    private var failedThisSession: Set<String> = []
    private var networkRetryAt: Date?
    private var wakeTask: Task<Void, Never>?
    private var automaticStarted = false
    private var busy = false
    private var settingsObserver: AnyCancellable?

    public private(set) var autoDownloadStatus: AutoDownloadStatus = .idle

    /// `catalog`, `root`, `environment`, `plan` and the session are injectable for the self-test; the defaults are the app's.
    public init(catalog: [ModelDescriptor] = ModelCatalog.all, root: @escaping () -> URL = { SuperFlowPaths.models },
                environment: DownloadEnvironment? = nil, plan: (() -> [ModelDescriptor])? = nil,
                retryDelays: [TimeInterval] = [1, 2, 4, 8],
                sessionConfiguration: ((_ automatic: Bool) -> URLSessionConfiguration)? = nil) {
        self.catalog = catalog
        self.root = root
        self.environment = environment ?? SystemDownloadEnvironment(volume: root)
        self.plan = plan ?? { ModelManager.automaticPlan() }
        self.retryDelays = retryDelays
        self.sessionConfiguration = sessionConfiguration ?? ModelManager.defaultConfiguration
        self.environment.onChange = { [weak self] in
            self?.networkRetryAt = nil
            self?.advance()
        }
    }

    nonisolated static func defaultConfiguration(automatic: Bool) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsExpensiveNetworkAccess = !automatic || AutoDownloadPolicy.allowsExpensiveNetwork
        configuration.allowsConstrainedNetworkAccess = !automatic || AutoDownloadPolicy.allowsConstrainedNetwork
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.httpMaximumConnectionsPerHost = AutoDownloadPolicy.maxConcurrentDownloads
        return configuration
    }

    /// What the automatic queue installs on this Mac: the preset in `AutoDownloadPolicy` order, the Silero VAD first
    /// when the app bundle carries no copy, and the multilingual Whisper fallback when a selected language (or
    /// auto-detect) is outside Parakeet's 25 (local-models.md §9.2, "Any, on demand").
    static func automaticPlan() -> [ModelDescriptor] {
        let preset = ModelCatalog.preset(isAppleSilicon: Machine.isAppleSilicon, memoryBytes: Machine.memoryBytes)
        var plan = AutoDownloadPolicy.order(for: preset)
        if bundledCopy(of: ModelCatalog.sileroVAD) == nil { plan.insert(ModelCatalog.sileroVAD, at: 0) }
        let languages = SpeechLanguages.requested(selected: Defaults[.selectedLanguages], autoDetect: Defaults[.autoDetectLanguage])
        if preset.dictation.contains(where: { $0.engine == "fluidaudio" && $0.kind == .asr }), !SpeechLanguages.parakeetCovers(languages),
           let fallback = ModelCatalog.descriptor(Defaults[.fallbackASRModelID]) {
            let lastASR = plan.lastIndex { $0.kind == .asr } ?? -1
            plan.insert(fallback, at: lastASR + 1)
        }
        var seen: Set<String> = []
        return plan.filter { seen.insert($0.id).inserted }
    }

    /// A copy shipped inside the app (`Contents/Resources/Models/<kind>/<file>`), used for the bundled VAD.
    nonisolated static func bundledCopy(of model: ModelDescriptor) -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("Models/\(model.kind.rawValue)/\(model.fileName)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: State

    private func descriptor(_ id: String) -> ModelDescriptor? { catalog.first { $0.id == id } }
    private func layout(_ model: ModelDescriptor) -> ModelLayout { ModelLayout(model, root: root()) }

    public func state(of id: String) -> ModelState {
        guard let model = descriptor(id) else { return .notDownloaded }
        if transfer?.id == id { return .downloading(fraction: fraction(id, model)) }
        let layout = layout(model)
        if layout.isInstalled() { return .installed }
        if damaged.contains(id) || FileManager.default.fileExists(atPath: layout.final.path) { return .damaged }
        if layout.partialBytes() > 0 { return .paused(fraction: fraction(id, model)) }
        if model.kind == .vad, ModelManager.bundledCopy(of: model) != nil { return .installed }
        return .notDownloaded
    }

    private func fraction(_ id: String, _ model: ModelDescriptor) -> Double {
        if let progress = progress[id], progress.bytesExpected > 0 { return min(1, progress.fraction) }
        guard model.bytes > 0 else { return 0 }
        return min(1, Double(layout(model).partialBytes()) / Double(model.bytes))
    }

    public func location(of id: String) -> URL? {
        guard let model = descriptor(id) else { return nil }
        let layout = layout(model)
        if transfer?.id != id, layout.isInstalled() { return layout.final }
        return model.kind == .vad ? ModelManager.bundledCopy(of: model) : nil
    }

    public var diskUsage: Int64 { ModelLayout.size(of: root()) }

    public var changes: AnyPublisher<String, Never> { changeSubject.eraseToAnyPublisher() }

    public func readiness(of id: String) -> Double? {
        guard let model = descriptor(id), state(of: id) != .installed else { return nil }
        if transfer?.id == id || explicitQueue.contains(id) { return fraction(id, model) }
        if automaticStarted, Defaults[.autoDownloadModels], plan().contains(where: { $0.id == id }), isCandidate(model) {
            return fraction(id, model)
        }
        return nil
    }

    // MARK: Explicit actions

    public func download(_ id: String) -> AsyncThrowingStream<DownloadProgress, Error> {
        let (stream, continuation) = AsyncThrowingStream<DownloadProgress, Error>.makeStream()
        guard let model = descriptor(id) else {
            continuation.finish(throwing: ModelError.unknownModel(id))
            return stream
        }
        if transfer?.id != id, layout(model).isInstalled() {
            continuation.finish()
            return stream
        }
        listeners[id, default: []].append(continuation)
        pausedByUser.remove(id)
        damaged.remove(id)
        failedThisSession.remove(id)
        Defaults[.speechKitRemovedModels].removeAll { $0 == id }
        if transfer?.id == id {
            transfer?.explicit = true
            return stream
        }
        explicitQueue.removeAll { $0 == id }
        explicitQueue.append(id)
        if let current = transfer, !current.explicit {
            current.task.cancel()   // the automatic transfer yields and resumes from its partial later
        } else {
            advance()
        }
        changeSubject.send(id)
        return stream
    }

    public func pause(_ id: String) {
        guard descriptor(id) != nil else { return }
        pausedByUser.insert(id)
        explicitQueue.removeAll { $0 == id }
        if transfer?.id == id {
            transfer?.task.cancel()
        } else {
            finishListeners(id, error: ModelError.cancelled)
        }
        changeSubject.send(id)
    }

    public func delete(_ id: String) throws {
        guard let model = descriptor(id) else { throw ModelError.unknownModel(id) }
        if !Defaults[.speechKitRemovedModels].contains(id) { Defaults[.speechKitRemovedModels].append(id) }
        explicitQueue.removeAll { $0 == id }
        damaged.remove(id)
        progress[id] = nil
        if transfer?.id == id {
            pendingDeletion.insert(id)
            transfer?.task.cancel()
            return
        }
        try removeFiles(layout(model))
        changeSubject.send(id)
    }

    private func removeFiles(_ layout: ModelLayout) throws {
        let fm = FileManager.default
        for url in [layout.final, layout.partial] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    public func importModel(_ id: String, from source: URL) async throws {
        guard let model = descriptor(id) else { throw ModelError.unknownModel(id) }
        guard transfer?.id != id else { throw ModelError.cancelled }
        let layout = layout(model)
        try await Task.detached(priority: .userInitiated) {
            try ModelManager.install(from: source, into: layout)
        }.value
        damaged.remove(id)
        pausedByUser.remove(id)
        Defaults[.speechKitRemovedModels].removeAll { $0 == id }
        changeSubject.send(id)
        Log.models.info("Imported \(id, privacy: .public)")
    }

    /// Verifies a user-supplied file (its SHA-256) or folder (every required entry) and moves a copy into place.
    nonisolated private static func install(from source: URL, into layout: ModelLayout) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: layout.partial.path) { try fm.removeItem(at: layout.partial) }
        if layout.isFolder {
            let missing = layout.requiredEntries.filter { !fm.fileExists(atPath: source.appendingPathComponent($0).path) }
            guard missing.isEmpty else { throw ModelError.checksumMismatch }
            try fm.createDirectory(at: layout.partial, withIntermediateDirectories: true)
            for entry in layout.requiredEntries {
                try fm.copyItem(at: source.appendingPathComponent(entry), to: layout.partial.appendingPathComponent(entry))
            }
        } else {
            var digest = StreamingDigest(layout.model.sha256.map(RemoteFile.Digest.sha256), size: layout.model.bytes)
            try digest.update(contentsOf: source)
            guard digest.matches() else { throw ModelError.checksumMismatch }
            try fm.copyItem(at: source, to: layout.partial)
        }
        try moveIntoPlace(layout)
    }

    /// Atomic swap of the verified partial (file or staging folder) into its final name.
    nonisolated private static func moveIntoPlace(_ layout: ModelLayout) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: layout.final.path) {
            _ = try fm.replaceItemAt(layout.final, withItemAt: layout.partial)
        } else {
            try fm.moveItem(at: layout.partial, to: layout.final)
        }
    }

    // MARK: Automatic queue

    public func startAutomaticDownloads() {
        if !automaticStarted {
            automaticStarted = true
            let keys: Set<String> = [Defaults.Keys.autoDownloadModels.name, Defaults.Keys.modelMirrorURL.name,
                                     Defaults.Keys.selectedLanguages.name, Defaults.Keys.autoDetectLanguage.name,
                                     Defaults.Keys.fallbackASRModelID.name]
            settingsObserver = Defaults.changes.filter { keys.contains($0) }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.settingsChanged() } }
        }
        advance()
    }

    public func setUserBusy(_ busy: Bool) {
        guard self.busy != busy else { return }
        self.busy = busy
        if busy, let current = transfer, !current.explicit, AutoDownloadPolicy.yieldsWhileBusy {
            current.task.cancel()
        } else if !busy {
            advance()
        }
    }

    private func settingsChanged() {
        if !Defaults[.autoDownloadModels], let current = transfer, !current.explicit { current.task.cancel() }
        advance()
    }

    private func isCandidate(_ model: ModelDescriptor) -> Bool {
        !pausedByUser.contains(model.id) && !failedThisSession.contains(model.id) && !damaged.contains(model.id)
            && !Defaults[.speechKitRemovedModels].contains(model.id) && !layout(model).isInstalled()
            && (model.url != nil || model.repository != nil)
            && !(model.kind == .vad && ModelManager.bundledCopy(of: model) != nil)
    }

    /// Starts the next transfer when none runs: explicit requests first, then the automatic plan if the policy allows.
    private func advance() {
        guard transfer == nil else { return }
        if !explicitQueue.isEmpty {
            start(explicitQueue.removeFirst(), explicit: true)
            return
        }
        guard automaticStarted else { return }
        let now = Date()
        var conditions = environment.conditions
        if let retry = networkRetryAt, retry > now { conditions.networkUsable = false }
        let blocker = AutoDownloadGate.blocker(enabled: Defaults[.autoDownloadModels], busy: busy, conditions: conditions,
                                               diskRetryAfter: Defaults[.autoDownloadDiskRetryAfter], now: now)
        if let blocker {
            if case .waitingForDisk = blocker, now.timeIntervalSince1970 >= Defaults[.autoDownloadDiskRetryAfter] {
                Defaults[.autoDownloadDiskRetryAfter] = now.addingTimeInterval(AutoDownloadPolicy.diskRetryInterval).timeIntervalSince1970
            }
            setStatus(blocker)
            scheduleWake(for: blocker, now: now)
            return
        }
        guard let next = plan().first(where: { descriptor($0.id) != nil && isCandidate($0) }) else {
            setStatus(.upToDate)
            return
        }
        start(next.id, explicit: false)
    }

    /// Re-checks later when the wait is time-based (the daily disk retry, a network back-off).
    private func scheduleWake(for status: AutoDownloadStatus, now: Date) {
        let at: Date?
        switch status {
        case .waitingForDisk: at = Date(timeIntervalSince1970: Defaults[.autoDownloadDiskRetryAfter])
        case .waitingForNetwork: at = networkRetryAt
        default: at = nil
        }
        wakeTask?.cancel()
        guard let at, at > now else { return }
        wakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(at.timeIntervalSince(now) * 1e9))
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func setStatus(_ status: AutoDownloadStatus) {
        guard autoDownloadStatus != status else { return }
        autoDownloadStatus = status
        Log.models.info("Automatic downloads: \(String(describing: status), privacy: .public)")
    }

    // MARK: Transfers

    private func start(_ id: String, explicit: Bool) {
        guard let model = descriptor(id) else { return }
        let layout = layout(model)
        let configuration = sessionConfiguration(!explicit)
        rateSamples = []
        let task = Task { [weak self] in
            var failure: Error?
            do {
                try await ModelManager.perform(layout, configuration: configuration, retryDelays: self?.retryDelays ?? []) { done, total in
                    Task { @MainActor in self?.report(id, done: done, total: total) }
                }
            } catch {
                failure = error
            }
            self?.finished(id, failure: failure)
        }
        transfer = Transfer(id: id, explicit: explicit, task: task)
        if !explicit {
            setStatus(.downloading(modelID: id, progress: progress[id] ?? DownloadProgress(bytesReceived: layout.partialBytes(),
                                                                                             bytesExpected: model.bytes)))
        }
        Log.models.info("Downloading \(id, privacy: .public) (\(explicit ? "requested" : "automatic", privacy: .public))")
        changeSubject.send(id)
    }

    /// Fetches every file of a model with per-file retries, then moves it into place.
    nonisolated private static func perform(_ layout: ModelLayout, configuration: URLSessionConfiguration, retryDelays: [TimeInterval],
                                            progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        let files: [RemoteFile]
        if layout.isFolder {
            files = try await retrying(retryDelays) {
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                return try await ModelSource.files(of: layout, session: session)
            }
        } else {
            files = ModelSource.files(of: layout.model)
        }
        guard !files.isEmpty else { throw ModelError.unknownModel(layout.model.id) }
        let total = max(files.reduce(0) { $0 + max(0, $1.size) }, layout.model.bytes)
        let onDisk = layout.partialBytes()
        let free = (try? layout.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        let needed = Int64(Double(max(0, total - onDisk)) * 1.1)
        guard free >= needed else { throw ModelError.notEnoughSpace(needed: needed) }

        var completed: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let target = layout.isFolder ? layout.partial.appendingPathComponent(file.path) : layout.partial
            if layout.isFolder, file.size >= 0, (try? fm.attributesOfItem(atPath: target.path))?[.size] as? Int64 == file.size {
                completed += file.size   // verified when it was moved into the staging folder
                continue
            }
            let partial = layout.isFolder ? target.appendingPathExtension("partial") : target
            let base = completed
            try await retrying(retryDelays) {
                try await FileTransfer(file: file, partial: partial, configuration: configuration) { bytes in
                    progress(base + bytes, total)
                }.run()
            }
            if layout.isFolder {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.moveItem(at: partial, to: target)
            }
            completed += max(0, file.size)
            progress(completed, total)
        }
        try moveIntoPlace(layout)
    }

    /// Retries transient network failures with back-off (1, 2, 4, 8 s); HTTP errors, hash mismatches and
    /// cancellation surface at once.
    nonisolated private static func retrying<T>(_ delays: [TimeInterval], _ body: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await body()
            } catch let error as URLError where attempt < delays.count && error.code != .cancelled {
                try await Task.sleep(nanoseconds: UInt64(delays[attempt] * 1e9))
                attempt += 1
            } catch is CancellationError {
                throw ModelError.cancelled
            }
        }
    }

    private func report(_ id: String, done: Int64, total: Int64) {
        guard transfer?.id == id else { return }
        let now = Date()
        rateSamples.append((now, done))
        rateSamples.removeAll { now.timeIntervalSince($0.time) > 5 }
        var rate = 0.0
        if let first = rateSamples.first, now.timeIntervalSince(first.time) > 0.2 {
            rate = Double(done - first.bytes) / now.timeIntervalSince(first.time)
        }
        let update = DownloadProgress(bytesReceived: done, bytesExpected: total, rate: max(0, rate))
        progress[id] = update
        if case .downloading(let current, _) = autoDownloadStatus, current == id {
            autoDownloadStatus = .downloading(modelID: id, progress: update)
        }
        let finishedFile = done == total
        if finishedFile || now.timeIntervalSince(lastNotified[id] ?? .distantPast) >= 0.25 {
            lastNotified[id] = now
            listeners[id]?.forEach { $0.yield(update) }
            changeSubject.send(id)
        }
    }

    private func finished(_ id: String, failure: Error?) {
        let wasExplicit = transfer?.explicit ?? false
        transfer = nil
        guard let model = descriptor(id) else { return }
        if pendingDeletion.remove(id) != nil {
            try? removeFiles(layout(model))
            progress[id] = nil
            finishListeners(id, error: ModelError.cancelled)
        } else if let failure {
            let error: Error = failure is CancellationError ? ModelError.cancelled : failure
            switch error as? ModelError {
            case .cancelled?:
                // Paused by the user, pre-empted by an explicit download, or yielding while busy: the partial stays.
                finishListeners(id, error: error)
            case .checksumMismatch?:
                damaged.insert(id)
                failedThisSession.insert(id)
                finishListeners(id, error: error)
            case .http?, .unknownModel?:
                failedThisSession.insert(id)
                finishListeners(id, error: error)
            case .notEnoughSpace?:
                finishListeners(id, error: error)
                if !wasExplicit {
                    Defaults[.autoDownloadDiskRetryAfter] = Date().addingTimeInterval(AutoDownloadPolicy.diskRetryInterval).timeIntervalSince1970
                }
            case nil:
                // Network trouble that outlasted the back-off: wait for the path to change, or five minutes.
                finishListeners(id, error: error)
                if !wasExplicit { networkRetryAt = Date().addingTimeInterval(300) }
            }
            Log.models.error("Download of \(id, privacy: .public) stopped: \(error.localizedDescription, privacy: .public)")
        } else {
            progress[id] = nil
            damaged.remove(id)
            let done = DownloadProgress(bytesReceived: model.bytes, bytesExpected: model.bytes)
            listeners[id]?.forEach { $0.yield(done) }
            finishListeners(id, error: nil)
            Log.models.info("Installed \(id, privacy: .public)")
        }
        changeSubject.send(id)
        advance()
    }

    private func finishListeners(_ id: String, error: Error?) {
        let waiting = listeners.removeValue(forKey: id) ?? []
        for continuation in waiting {
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }
}

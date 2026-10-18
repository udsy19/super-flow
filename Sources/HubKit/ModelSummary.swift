import Foundation
import SuperFlowCore

/// The one-glance state of the automatic model downloads (owner decision: models download on their own; the hub
/// shows status and never asks). Used by the sidebar badge, Home, onboarding and Settings › Models.
public struct ModelSummary: Equatable, Sendable {
    public var headline: String
    public var detail: String
    /// Progress of the download in flight, when there is one.
    public var fraction: Double?
    public var isComplete: Bool
    /// Whether the dictation speech model is installed (the "Try it" step and the Home banner key off this).
    public var speechReady: Bool

    /// - Parameters:
    ///   - queue: the preset's models in download order (`AutoDownloadPolicy.order(for:)`).
    public static func make(queue: [ModelDescriptor], state: (String) -> ModelState, status: AutoDownloadStatus) -> ModelSummary {
        let models = queue.filter { $0.kind != .vad }
        let speech = models.first { $0.kind == .asr }
        let speechReady = speech.map { state($0.id) == .installed } ?? true
        let missing = models.filter { state($0.id) != .installed }
        if missing.isEmpty {
            return ModelSummary(headline: "Models ready", detail: "Speech, cleanup and notes run on this Mac.", fraction: nil,
                                isComplete: true, speechReady: true)
        }
        let headline = speechReady ? "Downloading models" : "Getting dictation ready"
        let name = { (id: String) in ModelCatalog.descriptor(id)?.name ?? id }

        if case .downloading(let id, let progress) = status {
            return ModelSummary(headline: headline, detail: "\(name(id)) · \(percent(progress.fraction))", fraction: progress.fraction,
                                isComplete: false, speechReady: speechReady)
        }
        if let active = missing.first(where: { if case .downloading = state($0.id) { true } else { false } }),
           case .downloading(let fraction) = state(active.id) {
            return ModelSummary(headline: headline, detail: "\(active.name) · \(percent(fraction))", fraction: fraction,
                                isComplete: false, speechReady: speechReady)
        }
        let detail: String
        switch status {
        case .idle, .upToDate, .downloading:
            detail = "\(missing.count) of \(models.count) still to download"
        default:
            detail = HubFormat.autoDownloadText(status, modelName: name)
        }
        return ModelSummary(headline: headline, detail: detail, fraction: nil, isComplete: false, speechReady: speechReady)
    }

    static func percent(_ fraction: Double) -> String { "\(Int((min(max(fraction, 0), 1) * 100).rounded())) %" }

    /// The preset for this Mac in download order.
    static var queue: [ModelDescriptor] {
        AutoDownloadPolicy.order(for: ModelCatalog.preset(isAppleSilicon: Machine.isAppleSilicon, memoryBytes: Machine.memoryBytes))
    }

    @MainActor static func current() -> ModelSummary? {
        guard let models = Services.models else { return nil }
        return make(queue: queue, state: models.state(of:), status: models.autoDownloadStatus)
    }
}

@preconcurrency import CoreML
import FluidAudio
import Foundation
import SuperFlowCore

/// Post-meeting speaker split (local-models.md §8.4): FluidAudio's offline pipeline (pyannote Community-1
/// segmentation, WeSpeaker embeddings, PLDA, VBx) on the catalog's Core ML set, loaded from `Models/diarization/<id>`
/// without FluidAudio's own downloader.
public actor SpeakerDiarizer {
    public let directory: URL
    private var manager: OfflineDiarizerManager?

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() async throws {
        let start = Date()
        func model(_ name: String, _ units: MLComputeUnits) throws -> MLModel {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = units
            return try MLModel(contentsOf: directory.appendingPathComponent(name), configuration: configuration)
        }
        let models = OfflineDiarizerModels(
            segmentationModel: try model(ModelNames.OfflineDiarizer.segmentationFile, .all),
            fbankModel: try model(ModelNames.OfflineDiarizer.fbankFile, .cpuOnly),
            embeddingModel: try model(ModelNames.OfflineDiarizer.embeddingFile, .all),
            pldaRhoModel: try model(ModelNames.OfflineDiarizer.pldaRhoFile, .all),
            pldaPsi: try Self.pldaPsi(directory.appendingPathComponent(ModelNames.OfflineDiarizer.pldaParameters)),
            compilationDuration: Date().timeIntervalSince(start))
        let manager = OfflineDiarizerManager(config: .default)
        manager.initialize(models: models)
        self.manager = manager
    }

    /// Speaker turns in 16 kHz mono audio: (cluster label, start, end) in seconds from the clip start.
    public func diarize(_ samples: [Float]) async throws -> [(speaker: String, start: TimeInterval, end: TimeInterval)] {
        guard let manager else { throw SpeechError.engineUnavailable("The speaker model isn't loaded.") }
        let result = try await manager.process(audio: samples)
        return result.segments.map { ($0.speakerId, TimeInterval($0.startTimeSeconds), TimeInterval($0.endTimeSeconds)) }
    }

    /// The PLDA ψ vector from `plda-parameters.json` (`tensors.psi.data_base64`, little-endian Float32).
    static func pldaPsi(_ url: URL) throws -> [Double] {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tensors = root["tensors"] as? [String: Any], let psi = tensors["psi"] as? [String: Any],
              let base64 = psi["data_base64"] as? String,
              let raw = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), raw.count >= 4 else {
            throw SpeechError.failed("The speaker model's PLDA parameters are unreadable.")
        }
        var floats = [Float](repeating: 0, count: raw.count / 4)
        _ = floats.withUnsafeMutableBytes { raw.copyBytes(to: $0) }
        return floats.map(Double.init)
    }
}

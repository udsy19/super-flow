import Foundation
import FluidAudio
import SuperFlowCore

/// Parakeet TDT v3 via FluidAudio (local-models.md §2.3): precompiled Core ML on the ANE, loaded from the app's own
/// `Models/asr/<id>` folder rather than FluidAudio's cache, and warmed once after loading.
public actor ParakeetEngine {
    public let directory: URL
    private var manager: AsrManager?

    public init(directory: URL) {
        self.directory = directory
    }

    /// Whether every `.mlmodelc` component and the vocabulary are in `directory`.
    public static func modelsExist(at directory: URL) -> Bool {
        AsrModels.modelsExist(at: directory, version: .v3)
    }

    public func load() async throws {
        let models = try AsrModels.loadLocal(from: directory, version: .v3)
        let manager = AsrManager(config: .default, models: models)
        try await manager.loadModels(models)
        self.manager = manager
    }

    /// One second of silence end to end, so the ANE plans are built before the first dictation.
    public func warm() async {
        _ = try? await transcribe(AudioClip(samples: [Float](repeating: 0, count: AudioClip.sampleRate)))
    }

    public var isLoaded: Bool { manager != nil }

    /// Recognises one clip. `language` (one of Parakeet's 25) steers script-aware decoding; clips shorter than the
    /// model's minimum are padded with silence.
    public func transcribe(_ clip: AudioClip, language: String? = nil) async throws -> Transcript {
        guard let manager else { throw SpeechError.engineUnavailable("Parakeet isn't loaded.") }
        var samples = clip.samples
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: AudioClip.sampleRate) + AudioClip.sampleRate / 10
        if samples.count < minimum { samples += [Float](repeating: 0, count: minimum - samples.count) }
        var state = TdtDecoderState.make()
        let hint = language.flatMap { Language(rawValue: SupportedLanguages.base($0)) }
        let result = try await manager.transcribe(samples, decoderState: &state, language: hint)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let timings = result.tokenTimings ?? []
        var segments = Self.phrases(buildWordTimings(from: timings), offset: clip.startTime)
        if segments.isEmpty, !text.isEmpty {
            let start = clip.startTime + (timings.first?.startTime ?? 0)
            let end = clip.startTime + (timings.last?.endTime ?? clip.duration)
            segments = [TranscriptSegment(start: start, end: max(start, end), text: text)]
        }
        return Transcript(text: text, language: language.map(SupportedLanguages.base) ?? "", confidence: Double(result.confidence),
                          segments: text.isEmpty ? [] : segments)
    }

    /// A pause this long between two words starts a new phrase.
    static let phrasePause: TimeInterval = 0.6

    /// Words grouped into phrases at pauses, so a long clip (a meeting re-read in 30 s windows) keeps its timeline.
    static func phrases(_ words: [WordTiming], offset: TimeInterval) -> [TranscriptSegment] {
        var phrases: [TranscriptSegment] = []
        var current: [WordTiming] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            phrases.append(TranscriptSegment(start: offset + first.startTime, end: offset + max(first.startTime, last.endTime),
                                             text: current.map(\.word).joined(separator: " ")))
            current = []
        }
        for word in words {
            if let last = current.last, word.startTime - last.endTime >= phrasePause { close() }
            current.append(word)
        }
        close()
        return phrases
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
    }
}

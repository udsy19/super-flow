import Foundation
import SuperFlowCore
import whisper

// Voice activity detection (local-models.md §2.9, §8.5): Silero through whisper.cpp's VAD API on the catalog's ggml
// model (0.9 MB, both architectures), with an energy gate when the model is not on disk yet. Either one produces
// per-window speech probabilities; `SpeechRegions` and `StreamingSegmenter` turn them into regions.

/// Thresholds for turning probabilities into speech regions (Silero's defaults, with the pause lengths of §2.8/§8.3).
public struct VADParameters: Sendable {
    public var threshold: Float = 0.5
    /// Speech continues until the probability drops below this (hysteresis).
    public var releaseThreshold: Float = 0.35
    /// Shorter bursts are noise (also the "skip ASR" guard, §2.12).
    public var minimumSpeech: TimeInterval = 0.25
    /// A pause this long closes a segment: 300 ms while dictating, 400 ms in meetings.
    public var minimumSilence: TimeInterval = 0.3
    /// Kept around each region so word edges are not clipped.
    public var padding: TimeInterval = 0.1
    /// A segment closes at this length even without a pause (§8.3: 15 s).
    public var maximumSegment: TimeInterval = 15

    public init() {}

    public static let dictation = VADParameters()
    public static var meeting: VADParameters {
        var p = VADParameters()
        p.minimumSilence = 0.4
        return p
    }
}

/// A source of per-window speech probabilities.
public protocol SpeechProbabilityModel: AnyObject {
    /// Samples per probability (Silero: 512 = 32 ms).
    var window: Int { get }
    /// Probabilities for consecutive windows of `samples`; with `continuing`, the model keeps its state from the
    /// previous call (streaming). Only whole windows are scored.
    func probabilities(_ samples: [Float], continuing: Bool) -> [Float]
}

/// Silero VAD v6 through whisper.cpp (`whisper_vad_*`). One instance per stream: the LSTM state is per context.
public final class SileroVAD: SpeechProbabilityModel, @unchecked Sendable {
    public let window = 512
    private let context: OpaquePointer
    private let lock = NSLock()

    public init(modelURL: URL) throws {
        WhisperEngine.quietLogs
        var params = whisper_vad_default_context_params()
        params.n_threads = 1
        params.use_gpu = false
        guard let context = whisper_vad_init_from_file_with_params(modelURL.path, params) else {
            throw SpeechError.failed("Couldn't load the voice detector")
        }
        self.context = context
    }

    deinit { whisper_vad_free(context) }

    public func probabilities(_ samples: [Float], continuing: Bool) -> [Float] {
        let usable = samples.count / window * window
        guard usable > 0 else { return [] }
        return lock.withLock {
            if !continuing { whisper_vad_reset_state(context) }
            let ok = samples.withUnsafeBufferPointer { whisper_vad_detect_speech_no_reset(context, $0.baseAddress, Int32(usable)) }
            guard ok, let probs = whisper_vad_probs(context) else { return [] }
            return Array(UnsafeBufferPointer(start: probs, count: Int(whisper_vad_n_probs(context))))
        }
    }
}

/// The fallback before Silero is installed: speech when a 32 ms window is loud and well above an adaptive noise floor.
public final class EnergyVAD: SpeechProbabilityModel, @unchecked Sendable {
    public let window = 512
    private var noiseFloor: Float?
    private let lock = NSLock()

    public init() {}

    public func probabilities(_ samples: [Float], continuing: Bool) -> [Float] {
        lock.withLock {
            if !continuing { noiseFloor = nil }
            var result: [Float] = []
            var start = 0
            while start + window <= samples.count {
                var sum: Float = 0
                for s in samples[start..<start + window] { sum += s * s }
                let db = 10 * log10(sum / Float(window) + 1e-12)
                // The floor falls at once and rises slowly (≈3 dB/s), so pauses between words keep resetting it.
                let floor = noiseFloor.map { db < $0 ? db : $0 + 0.1 } ?? db
                noiseFloor = floor
                let loudness = min(1, max(0, (db + 55) / 10))          // −55…−45 dBFS ramps in
                let contrast = min(1, max(0, (db - max(floor, -70) - 6) / 12))  // 6…18 dB above the floor
                result.append(min(loudness, contrast))
                start += window
            }
            return result
        }
    }
}

/// Probabilities → speech regions as sample ranges, with padding, merging and the minimum lengths.
public enum SpeechRegions {
    public static func regions(probabilities: [Float], window: Int, totalSamples: Int, parameters p: VADParameters = .dictation) -> [Range<Int>] {
        var segmenter = StreamingSegmenter(window: window, parameters: p)
        var closed = segmenter.push(probabilities)
        if let open = segmenter.finish(totalSamples: totalSamples) { closed.append(open) }
        return closed
    }
}

/// Incremental segmentation for a live stream: push probabilities as audio arrives, get regions back as pauses close
/// them; `open` is the region still being spoken.
public struct StreamingSegmenter: Sendable {
    public let window: Int
    public let parameters: VADParameters
    private var index = 0
    private var speechStart: Int?
    private var lastSpeech = 0
    private var previousEnd = 0
    private var minimumSpeech: Int { Int(parameters.minimumSpeech * Double(AudioClip.sampleRate)) }
    private var minimumSilence: Int { Int(parameters.minimumSilence * Double(AudioClip.sampleRate)) }
    private var padding: Int { Int(parameters.padding * Double(AudioClip.sampleRate)) }
    private var maximumSegment: Int { Int(parameters.maximumSegment * Double(AudioClip.sampleRate)) }

    public init(window: Int, parameters: VADParameters) {
        self.window = window
        self.parameters = parameters
    }

    /// Samples scored so far.
    public var position: Int { index * window }

    /// The region currently being spoken (padded start to the latest sample), if any.
    public var open: Range<Int>? {
        guard let speechStart else { return nil }
        return max(previousEnd, speechStart - padding)..<max(position, speechStart + 1)
    }

    /// Feeds the next windows' probabilities; returns regions closed by a long enough pause or the length cap.
    public mutating func push(_ probabilities: [Float]) -> [Range<Int>] {
        var closed: [Range<Int>] = []
        for p in probabilities {
            let start = index * window
            let end = start + window
            index += 1
            if let begin = speechStart {
                if p >= parameters.releaseThreshold { lastSpeech = end }
                if end - lastSpeech >= minimumSilence {
                    if let region = close(begin: begin, end: lastSpeech) { closed.append(region) }
                } else if end - begin >= maximumSegment {
                    if let region = close(begin: begin, end: end, padEnd: false) { closed.append(region) }
                    if p >= parameters.threshold { speechStart = end; lastSpeech = end }
                }
            } else if p >= parameters.threshold {
                speechStart = start
                lastSpeech = end
            }
        }
        return closed
    }

    /// Ends the stream: the open region (if long enough) up to `totalSamples`.
    public mutating func finish(totalSamples: Int) -> Range<Int>? {
        guard let begin = speechStart else { return nil }
        let end = min(totalSamples, max(lastSpeech, begin))
        return close(begin: begin, end: end, limit: totalSamples)
    }

    private mutating func close(begin: Int, end: Int, padEnd: Bool = true, limit: Int? = nil) -> Range<Int>? {
        speechStart = nil
        guard end - begin >= minimumSpeech else { return nil }
        let lower = max(previousEnd, begin - padding)
        var upper = padEnd ? end + padding : end
        if let limit { upper = min(upper, limit) }
        guard upper > lower else { return nil }
        previousEnd = upper
        return lower..<upper
    }
}

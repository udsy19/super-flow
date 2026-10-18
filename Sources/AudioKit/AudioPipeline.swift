import AVFoundation
import SuperFlowCore

// The capture-independent half of AudioKit: any PCM buffer in, 40 ms frames of 16 kHz mono Float32 out, with the
// Flow Bar level (local-models.md §9.1, ui-reference.md §2.7). The microphone tap, the process tap and the
// ScreenCaptureKit fallback all feed one of these, so the self-test can drive it with synthetic buffers.

/// The adaptive level scaler (ui-reference.md §2.7): the floor starts at 0 dB, follows the quietest level seen and never
/// goes below −60 dB; the level is how far above the floor the frame is, over a 20 dB range.
public struct LevelScaler: Sendable {
    public static let minimumFloor: Float = -60
    public static let range: Float = 20
    public private(set) var floor: Float = 0

    public init() {}

    public mutating func level(rms: Float) -> Float {
        let db = 20 * log10(rms + 1e-10)
        floor = max(LevelScaler.minimumFloor, min(floor, db))
        return min(1, max(0, (db - floor) / LevelScaler.range))
    }

    public static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}

/// Converts buffers of any format to 16 kHz mono Float32 and cuts them into `frameLength`-sample frames stamped with
/// host time. Each capture owns one; a lock keeps `finish()` on the stopping thread safe against a tap callback still
/// in flight.
public final class FrameAssembler: @unchecked Sendable {
    /// 640 samples = 40 ms at 16 kHz (local-models.md §1.1, §9.1).
    public static let frameLength = 640
    public static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioClip.sampleRate),
                                                   channels: 1, interleaved: false)!

    public let channel: AudioChannel
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private var pending: [Float] = []
    /// Host time of `pending[0]`.
    private var pendingTime: TimeInterval?
    private var scaler = LevelScaler()

    public init(channel: AudioChannel) {
        self.channel = channel
    }

    /// Converts `buffer` and returns every complete frame. `hostTime` is when the buffer's first sample was captured
    /// (seconds on the `mach_absolute_time` clock); nil continues from the previous buffer. The sample-rate converter
    /// holds a few milliseconds back until the next buffer or `finish()`.
    public func append(_ buffer: AVAudioPCMBuffer, hostTime: TimeInterval?) -> [AudioFrame] {
        lock.withLock {
            guard buffer.frameLength > 0, let samples = convert(buffer, endOfStream: false) else { return [] }
            if pendingTime == nil || (pending.isEmpty && hostTime != nil) {
                pendingTime = hostTime ?? pendingTime ?? 0
            }
            pending += samples
            return takeFrames(padding: false)
        }
    }

    /// Drains the converter and returns the remaining audio, the last frame padded with silence; then resets.
    public func finish() -> [AudioFrame] {
        lock.withLock {
            if converter != nil, let tail = convert(nil, endOfStream: true) { pending += tail }
            let frames = takeFrames(padding: true)
            resetLocked()
            return frames
        }
    }

    /// Drops buffered samples and the converter (a new capture session or a format change).
    public func reset() {
        lock.withLock { resetLocked() }
    }

    private func resetLocked() {
        converter = nil
        converterInput = nil
        pending = []
        pendingTime = nil
    }

    private func takeFrames(padding: Bool) -> [AudioFrame] {
        let length = FrameAssembler.frameLength
        if padding, pending.count % length != 0 { pending += [Float](repeating: 0, count: length - pending.count % length) }
        var frames: [AudioFrame] = []
        var offset = 0
        while pending.count - offset >= length {
            let slice = pending[offset..<offset + length]
            let time = (pendingTime ?? 0) + Double(offset) / Double(AudioClip.sampleRate)
            frames.append(AudioFrame(channel: channel, samples: Array(slice), time: time,
                                     level: scaler.level(rms: LevelScaler.rms(slice))))
            offset += length
        }
        if offset > 0 {
            pending.removeFirst(offset)
            pendingTime = (pendingTime ?? 0) + Double(offset) / Double(AudioClip.sampleRate)
        }
        return frames
    }

    private func convert(_ buffer: AVAudioPCMBuffer?, endOfStream: Bool) -> [Float]? {
        let target = FrameAssembler.outputFormat
        if let buffer {
            let format = buffer.format
            if format.commonFormat == .pcmFormatFloat32, format.channelCount == 1, format.sampleRate == target.sampleRate,
               let data = buffer.floatChannelData, converter == nil {
                return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
            }
            if converter == nil || converterInput != format {
                guard let made = AVAudioConverter(from: format, to: target) else {
                    Log.audio.error("No converter from \(format.description, privacy: .public)")
                    return nil
                }
                made.downmix = true
                made.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
                converter = made
                converterInput = format
            }
        }
        guard let converter, let input = converterInput else { return nil }
        let frames = Double(buffer?.frameLength ?? 0)
        let capacity = AVAudioFrameCount((frames * target.sampleRate / input.sampleRate).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = buffer == nil
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = output.floatChannelData else {
            Log.audio.error("Conversion failed: \(error?.localizedDescription ?? "", privacy: .public)")
            return nil
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}

/// Fans frames out to every subscriber (each `frames` access is its own stream, so MeetingKit and the dictation
/// coordinator can both listen) and keeps the last `DictationLimits.preRoll` of microphone audio, which a stream that
/// subscribes while the microphone is already running receives first.
public final class FrameHub: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<AudioFrame>.Continuation] = [:]
    private var history: [AudioFrame] = []
    private let historyDuration: TimeInterval

    public init(historyDuration: TimeInterval = DictationLimits.preRoll) {
        self.historyDuration = historyDuration
    }

    public var subscriberCount: Int { lock.withLock { subscribers.count } }

    public func stream() -> AsyncStream<AudioFrame> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(4096))
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.lock.withLock { self.subscribers.removeValue(forKey: id) }
        }
        let seed: [AudioFrame] = lock.withLock {
            subscribers[id] = continuation
            return history
        }
        for frame in seed { continuation.yield(frame) }
        return stream
    }

    public func publish(_ frames: [AudioFrame]) {
        guard !frames.isEmpty else { return }
        let targets: [AsyncStream<AudioFrame>.Continuation] = lock.withLock {
            for frame in frames where frame.channel == .mic { history.append(frame) }
            // Keep the fewest recent frames that still cover `historyDuration`.
            if let last = history.last {
                let end = last.time + FrameAssembler.frameDuration
                while history.count > 1, end - history[1].time >= historyDuration - 1e-6 { history.removeFirst() }
            }
            return Array(subscribers.values)
        }
        for continuation in targets {
            for frame in frames { continuation.yield(frame) }
        }
    }

    /// Forgets the pre-roll (the microphone stopped; old audio must never prefix a later dictation).
    public func clearHistory() {
        lock.withLock { history = [] }
    }

    public func finishAll() {
        let targets = lock.withLock { () -> [AsyncStream<AudioFrame>.Continuation] in
            defer { subscribers = [:] }
            return Array(subscribers.values)
        }
        targets.forEach { $0.finish() }
    }
}

/// Averages microphone levels over `interval` of audio time (ui-reference.md §2.7 batching: 150 ms).
public struct LevelBatcher: Sendable {
    public static let interval: TimeInterval = 0.15
    private var sum: Float = 0
    private var count = 0
    private var started: TimeInterval?

    public init() {}

    /// Adds a frame's level; returns the batch average once `interval` of audio has accumulated.
    public mutating func add(_ frame: AudioFrame) -> Float? {
        if started == nil { started = frame.time }
        sum += frame.level
        count += 1
        guard let started, frame.time + FrameAssembler.frameDuration - started >= LevelBatcher.interval - 1e-6 else { return nil }
        let average = sum / Float(count)
        sum = 0
        count = 0
        self.started = nil
        return average
    }

    public mutating func reset() { self = LevelBatcher() }
}

public extension FrameAssembler {
    static var frameDuration: TimeInterval { Double(frameLength) / Double(AudioClip.sampleRate) }
}

extension AVAudioTime {
    /// Seconds on the host clock for this timestamp, or nil when it carries no host time.
    var hostSeconds: TimeInterval? {
        isHostTimeValid ? AVAudioTime.seconds(forHostTime: hostTime) : nil
    }
}

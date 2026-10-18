import AVFoundation
import Foundation
import SuperFlowCore

// Per-channel audio for a meeting (behaviour.md §20.4.6, local-models.md §8.2–8.3): 16 kHz mono samples are appended to
// raw 16-bit PCM chunk files while recording (every byte written survives a crash or quit), cut into utterances for the
// live transcript, and turned into one AAC file per channel once the meeting is processed.

/// One closed stretch of speech on a channel, with times relative to the recording start.
public struct Utterance: Sendable {
    public var samples: [Float]
    public var start: TimeInterval
    public var end: TimeInterval { start + Double(samples.count) / Double(AudioClip.sampleRate) }
}

/// Energy segmenter with an adaptive noise floor: an utterance closes at a pause of 400 ms or at 15 s
/// (local-models.md §8.3). The speech engine's own VAD then decides whether it holds speech.
public struct SpeechSegmenter {
    public static let pause: TimeInterval = 0.4
    public static let maxLength: TimeInterval = 15
    public static let minSpeech: TimeInterval = 0.25
    public static let padding: TimeInterval = 0.2
    private static let block = 320  // 20 ms

    private var position = 0          // samples consumed so far
    private var pending: [Float] = [] // < one block, waiting for more samples
    private var current: [Float] = []
    private var currentStart = 0
    private var voiced = 0
    private var silentRun = 0
    private var history: [Float] = [] // the last `padding` of audio while idle, so a word's onset is kept
    private var noiseFloor: Float = 0.002

    /// `startSample` places the first sample on the recording's timeline (a recovered tail starts mid-recording).
    public init(startSample: Int = 0) {
        position = startSample
    }

    private static func samples(_ seconds: TimeInterval) -> Int { Int(seconds * Double(AudioClip.sampleRate)) }

    /// Feeds samples; returns the utterances that closed.
    public mutating func append(_ samples: [Float]) -> [Utterance] {
        pending += samples
        var closed: [Utterance] = []
        var offset = 0
        while pending.count - offset >= Self.block {
            if let utterance = consume(Array(pending[offset..<offset + Self.block])) { closed.append(utterance) }
            offset += Self.block
        }
        pending.removeFirst(offset)
        return closed
    }

    /// Closes whatever is open (end of recording).
    public mutating func flush() -> Utterance? {
        if !current.isEmpty { current += pending }
        pending = []
        return close()
    }

    private mutating func consume(_ block: [Float]) -> Utterance? {
        defer { position += block.count }
        let rms = (block.reduce(0) { $0 + $1 * $1 } / Float(block.count)).squareRoot()
        let isVoiced = rms > max(0.01, noiseFloor * 3)
        if !isVoiced { noiseFloor = max(0.0005, noiseFloor * 0.95 + rms * 0.05) }

        if current.isEmpty {
            guard isVoiced else {
                history = Array((history + block).suffix(Self.samples(Self.padding)))
                return nil
            }
            current = history + block
            currentStart = position - history.count
            history = []
            voiced = block.count
            silentRun = 0
            return nil
        }
        current += block
        if isVoiced { voiced += block.count; silentRun = 0 } else { silentRun += block.count }
        if silentRun >= Self.samples(Self.pause) {
            // Keep a little of the trailing silence; the rest starts the next onset history.
            let trim = max(0, silentRun - Self.samples(Self.padding))
            history = Array(current.suffix(min(trim, Self.samples(Self.padding))))
            current.removeLast(trim)
            return close()
        }
        if current.count >= Self.samples(Self.maxLength) { return close() }
        return nil
    }

    private mutating func close() -> Utterance? {
        defer { current = []; voiced = 0; silentRun = 0 }
        guard voiced >= Self.samples(Self.minSpeech) else { return nil }
        return Utterance(samples: current, start: Double(currentStart) / Double(AudioClip.sampleRate))
    }
}

/// Appends one channel to `<channel>-00000.pcm`, `<channel>-00001.pcm`, … (16-bit little-endian PCM, 30 s each).
public final class ChunkedTrackWriter {
    public static let chunkSeconds = 30
    public static var chunkSamples: Int { chunkSeconds * AudioClip.sampleRate }

    public let folder: URL
    public let channel: AudioChannel
    private var handle: FileHandle?
    private var chunkIndex: Int
    private var samplesInChunk = 0
    public private(set) var totalSamples: Int

    /// Continues after any chunks already in the folder (a recovered recording keeps its timeline).
    public init(folder: URL, channel: AudioChannel) {
        self.folder = folder
        self.channel = channel
        let existing = Self.chunks(in: folder, channel: channel)
        chunkIndex = existing.count
        totalSamples = existing.reduce(0) { $0 + Self.sampleCount(of: $1) }
    }

    deinit { try? handle?.close() }

    public func append(_ samples: [Float]) throws {
        var offset = 0
        while offset < samples.count {
            if handle == nil || samplesInChunk >= Self.chunkSamples { try openNextChunk() }
            let count = min(samples.count - offset, Self.chunkSamples - samplesInChunk)
            try handle?.write(contentsOf: Self.pcm16(samples[offset..<offset + count]))
            samplesInChunk += count
            totalSamples += count
            offset += count
        }
    }

    public func close() {
        try? handle?.close()
        handle = nil
    }

    private func openNextChunk() throws {
        try handle?.close()
        let url = folder.appendingPathComponent(String(format: "%@-%05d.pcm", channel.rawValue, chunkIndex))
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: url)
        chunkIndex += 1
        samplesInChunk = 0
    }

    // MARK: Reading back

    public static func chunks(in folder: URL, channel: AudioChannel) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(channel.rawValue + "-") && $0.hasSuffix(".pcm") }.sorted()
            .map { folder.appendingPathComponent($0) }
    }

    public static func sampleCount(of chunk: URL) -> Int {
        ((try? chunk.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 2
    }

    /// The channel's samples from `fromSample` on, read from its chunks.
    public static func read(folder: URL, channel: AudioChannel, fromSample: Int = 0) -> [Float] {
        var samples: [Float] = []
        var skip = fromSample
        for chunk in chunks(in: folder, channel: channel) {
            guard let data = try? Data(contentsOf: chunk) else { continue }
            let count = data.count / 2
            if skip >= count { skip -= count; continue }
            data.withUnsafeBytes { raw in
                let values = raw.bindMemory(to: Int16.self)
                samples.reserveCapacity(samples.count + count - skip)
                for i in skip..<count { samples.append(Float(Int16(littleEndian: values[i])) / 32767) }
            }
            skip = 0
        }
        return samples
    }

    private static func pcm16(_ samples: ArraySlice<Float>) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for (i, sample) in samples.enumerated() {
                out[i] = Int16(max(-1, min(1, sample)) * 32767).littleEndian
            }
        }
        return data
    }
}

/// Final per-channel files: AAC (32 kbps, 16 kHz mono, about 14 MB an hour) in `<channel>.m4a`.
public enum MeetingAudioFiles {
    public static let bitRate = 32_000

    public static func fileName(_ channel: AudioChannel) -> String { channel.rawValue + ".m4a" }

    /// Encodes the channel's chunks into its final file and deletes the chunks; nil when the channel has no audio.
    /// Encoding again replaces an earlier file, so an interrupted run can simply be repeated.
    public static func finalize(folder: URL, channel: AudioChannel) throws -> AudioTrack? {
        let chunks = ChunkedTrackWriter.chunks(in: folder, channel: channel)
        guard !chunks.isEmpty else { return existingTrack(folder: folder, channel: channel) }
        let samples = ChunkedTrackWriter.read(folder: folder, channel: channel)
        let url = folder.appendingPathComponent(fileName(channel))
        if !samples.isEmpty {
            try? FileManager.default.removeItem(at: url)
            try encode(samples, to: url)
        }
        for chunk in chunks { try? FileManager.default.removeItem(at: chunk) }
        guard !samples.isEmpty else { return nil }
        return AudioTrack(channel: channel, file: fileName(channel), duration: Double(samples.count) / Double(AudioClip.sampleRate),
                          byteSize: fileSize(url))
    }

    private static func existingTrack(folder: URL, channel: AudioChannel) -> AudioTrack? {
        let url = folder.appendingPathComponent(fileName(channel))
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return AudioTrack(channel: channel, file: fileName(channel), duration: Double(file.length) / file.fileFormat.sampleRate,
                          byteSize: fileSize(url))
    }

    public static func encode(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioClip.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: bitRate]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let block = 16 * AudioClip.sampleRate
        var offset = 0
        while offset < samples.count {
            let count = min(block, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress! + offset, count: count) }
            try file.write(from: buffer)
            offset += count
        }
    }

    /// Decodes a final file back to 16 kHz mono samples (re-processing after the chunks are gone).
    public static func decode(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == Double(AudioClip.sampleRate), file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func fileSize(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}

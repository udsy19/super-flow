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
            let count = sampleCount(of: chunk)
            if skip >= count { skip -= count; continue }
            samples += read(chunk, skipping: skip)
            skip = 0
        }
        return samples
    }

    /// One chunk's samples after the first `skip`.
    static func read(_ chunk: URL, skipping skip: Int = 0) -> [Float] {
        guard let data = try? Data(contentsOf: chunk) else { return [] }
        let count = data.count / 2
        guard skip < count else { return [] }
        return data.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: Int16.self)
            return (skip..<count).map { Float(Int16(littleEndian: values[$0])) / 32767 }
        }
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
    /// The encoder writes here; the final name only ever holds a complete file.
    static func encodingName(_ channel: AudioChannel) -> String { channel.rawValue + ".encoding.m4a" }
    /// Present while the chunks are deleted after the final file went in: that file already holds all of them.
    static func encodedMarker(_ channel: AudioChannel) -> String { channel.rawValue + ".encoded" }

    /// Encodes the channel's chunks into its final file and deletes the chunks; nil when the channel has no audio.
    /// Every step survives being interrupted (a crash, a quit, a full disk) and simply runs again: the chunks are only
    /// deleted once the complete new file has atomically replaced the old one, and a marker says so meanwhile.
    public static func finalize(folder: URL, channel: AudioChannel) throws -> AudioTrack? {
        let fm = FileManager.default
        let chunks = ChunkedTrackWriter.chunks(in: folder, channel: channel)
        let url = folder.appendingPathComponent(fileName(channel))
        let marker = folder.appendingPathComponent(encodedMarker(channel))
        let total = chunks.reduce(0) { $0 + ChunkedTrackWriter.sampleCount(of: $1) }
        var encoded: Int?
        if total > 0, !fm.fileExists(atPath: marker.path) {
            let partial = folder.appendingPathComponent(encodingName(channel))
            try? fm.removeItem(at: partial)
            try encode(chunks, to: partial)
            guard rename(partial.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            guard fm.createFile(atPath: marker.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            encoded = total
        }
        for chunk in chunks { try? fm.removeItem(at: chunk) }
        try? fm.removeItem(at: marker)
        guard let encoded else { return existingTrack(folder: folder, channel: channel) }
        return AudioTrack(channel: channel, file: fileName(channel), duration: Double(encoded) / Double(AudioClip.sampleRate),
                          byteSize: fileSize(url))
    }

    /// Whether the channel's audio is (or is about to be) only in its final file.
    static func isEncoded(folder: URL, channel: AudioChannel) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(encodedMarker(channel)).path)
            || ChunkedTrackWriter.chunks(in: folder, channel: channel).isEmpty
    }

    /// The channel's samples from `fromSample` on, all at once (the speaker split needs the whole track). Transcription
    /// reads with `MeetingAudioReader` instead.
    public static func samples(folder: URL, channel: AudioChannel, fromSample: Int = 0) -> [Float] {
        guard let reader = MeetingAudioReader(folder: folder, channel: channel, fromSample: fromSample) else { return [] }
        var samples: [Float] = []
        while let block = reader.next() { samples += block }
        return samples
    }

    /// Whether the channel has any recorded audio, in chunks or in its final file, without reading it.
    public static func hasAudio(folder: URL, channel: AudioChannel) -> Bool {
        if !isEncoded(folder: folder, channel: channel) {
            return ChunkedTrackWriter.chunks(in: folder, channel: channel).contains { ChunkedTrackWriter.sampleCount(of: $0) > 0 }
        }
        return (existingTrack(folder: folder, channel: channel)?.duration ?? 0) > 0
    }

    /// Seconds recorded in the folder: the longest channel, in chunks or in its final file.
    public static func recordedDuration(folder: URL) -> TimeInterval {
        AudioChannel.allCases.map { channel -> TimeInterval in
            let chunked = ChunkedTrackWriter.chunks(in: folder, channel: channel).reduce(0) { $0 + ChunkedTrackWriter.sampleCount(of: $1) }
            let encoded = existingTrack(folder: folder, channel: channel)?.duration ?? 0
            return max(Double(chunked) / Double(AudioClip.sampleRate), encoded)
        }.max() ?? 0
    }

    private static func existingTrack(folder: URL, channel: AudioChannel) -> AudioTrack? {
        let url = folder.appendingPathComponent(fileName(channel))
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return AudioTrack(channel: channel, file: fileName(channel), duration: Double(file.length) / file.fileFormat.sampleRate,
                          byteSize: fileSize(url))
    }

    /// Encodes chunk by chunk, so a long meeting never sits in memory whole. The file is closed when this returns.
    private static func encode(_ chunks: [URL], to url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioClip.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: bitRate]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        for chunk in chunks {
            let samples = ChunkedTrackWriter.read(chunk)
            guard !samples.isEmpty else { continue }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            try file.write(from: buffer)
        }
    }

    private static func fileSize(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}

/// A channel's recorded audio from `fromSample` on, block by block: from its chunks while it is still recorded in
/// chunks, else from its final file. "Retry transcript" on a long meeting reads it this way, so the recording (an hour is
/// 230 MB as samples) is never in memory whole. `next()` does blocking file reads: call it off the main actor.
public final class MeetingAudioReader: @unchecked Sendable {
    /// Samples per block (30 s, one chunk).
    public static var blockSamples: Int { ChunkedTrackWriter.chunkSamples }

    private var chunks: [URL] = []
    private var skip = 0
    private var file: AVAudioFile?
    private var buffer: AVAudioPCMBuffer?

    /// Nil when the channel's final file can't be read.
    public init?(folder: URL, channel: AudioChannel, fromSample: Int = 0) {
        if !MeetingAudioFiles.isEncoded(folder: folder, channel: channel) {
            chunks = ChunkedTrackWriter.chunks(in: folder, channel: channel)
            skip = fromSample
            return
        }
        let url = folder.appendingPathComponent(MeetingAudioFiles.fileName(channel))
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.processingFormat.sampleRate == Double(AudioClip.sampleRate), file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else { return nil }
        file.framePosition = AVAudioFramePosition(min(Int64(fromSample), file.length))
        self.file = file
        self.buffer = buffer
    }

    /// The next block, or nil at the end.
    public func next() -> [Float]? {
        if let file, let buffer {
            // Small reads to the end: one large `read(into:)` stops at the last whole packet and drops the tail.
            var block: [Float] = []
            while block.count < Self.blockSamples, file.framePosition < file.length {
                guard (try? file.read(into: buffer, frameCount: min(buffer.frameCapacity, AVAudioFrameCount(Self.blockSamples - block.count)))) != nil,
                      buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
                block.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
            return block.isEmpty ? nil : block
        }
        while !chunks.isEmpty {
            let chunk = chunks.removeFirst()
            let count = ChunkedTrackWriter.sampleCount(of: chunk)
            if skip >= count { skip -= count; continue }
            let samples = ChunkedTrackWriter.read(chunk, skipping: skip)
            skip = 0
            if !samples.isEmpty { return samples }
        }
        return nil
    }
}

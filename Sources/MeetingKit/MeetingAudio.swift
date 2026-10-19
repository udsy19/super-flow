import AVFoundation
import Foundation
import SuperFlowCore

// Per-channel audio for a meeting (behaviour.md §20.4.6, local-models.md §8.2–8.3): 16 kHz mono samples are appended to
// raw 16-bit PCM chunk files while recording (every byte written survives a crash or quit), levelled and cut into
// utterances for the live transcript, and turned into one AAC file per channel once the meeting is processed.

/// One stretch of speech on a channel, with times relative to the recording start. `id` is the same for the stretch
/// while it is still being spoken (live partials) and once it closed (the final segment replaces them).
public struct Utterance: Sendable {
    public var id: UUID
    public var samples: [Float]
    public var start: TimeInterval
    public var end: TimeInterval { start + Double(samples.count) / Double(AudioClip.sampleRate) }
}

/// Level of a block in dBFS (mean square), −120 for digital silence.
func decibels(_ samples: ArraySlice<Float>) -> Float {
    guard !samples.isEmpty else { return -120 }
    var sum: Float = 0
    for s in samples { sum += s * s }
    return max(-120, 10 * log10(sum / Float(samples.count) + 1e-12))
}

/// Automatic gain for one track before it is segmented and recognised (the recording on disk keeps the raw level). A
/// quiet laptop microphone is brought up so the loud end of speech sits near `target`, by at most `maximumGain`; louder
/// tracks are left alone. The gain follows only the level of speech, never pauses or room noise, so it doesn't pump, and
/// no block is pushed past `ceiling`.
public struct LevelNormalizer: Sendable {
    public static let target: Float = -20
    public static let maximumGain: Float = 30
    static let ceiling: Float = 0.9
    /// Blocks this far above the noise floor count as speech for the level estimate.
    static let speechMargin: Float = 10

    /// Starts low, so a track that is digital silence between words (a muted far end, a test tone) still finds its speech.
    private var floor: Float = -70
    private var speech: Float?
    private var gain: Float = 0
    private var applied: Float = 0
    /// The gain (dB) applied at the end of the last block.
    public var currentGain: Float { applied }

    public init() {}

    /// Levels one block (20 ms blocks keep the gain smooth).
    public mutating func process(_ block: [Float]) -> [Float] {
        guard !block.isEmpty else { return block }
        let level = decibels(block[...])
        if level > -100 {
            floor = min(level, floor + 0.05)
            if level > floor + Self.speechMargin, level > -70 {
                // Fast up, slow down: the estimate sits near the loud end of the speech.
                speech = speech.map { $0 + (level - $0) * (level > $0 ? 0.1 : 0.02) } ?? level
            }
        }
        let wanted = speech.map { min(Self.maximumGain, max(0, Self.target - $0)) } ?? 0
        gain += max(-1, min(1, wanted - gain))
        let peak = block.reduce(0) { max($0, abs($1)) }
        let limit = peak > 0 ? 20 * log10(Self.ceiling / peak) : Self.maximumGain
        let end = min(gain, limit), start = min(applied, limit)
        applied = end
        guard start != 0 || end != 0 else { return block }
        let from = pow(10, start / 20), to = pow(10, end / 20)
        let step = (to - from) / Float(block.count)
        return block.enumerated().map { i, s in s * (from + step * Float(i)) }
    }
}

/// Consecutive utterances of one track, levelled, for one decode with context (the refine pass).
public struct RefineWindow: Sendable {
    /// The utterances it covers: their live segments are what the refined text replaces.
    public var utteranceIDs: [UUID]
    public var samples: [Float]
    public var start: TimeInterval
    public var end: TimeInterval { start + Double(samples.count) / Double(AudioClip.sampleRate) }
}

/// Energy segmenter on the levelled track (local-models.md §8.3): a block is voiced when it stands `margin` above the
/// noise floor, which drops to any quieter block at once and creeps up 2.5 dB/s, so a quiet microphone, a loud room or
/// a far end that is digital silence between words all segment alike. An utterance closes at a pause of `pause`, or at
/// `maxLength` on the quietest moment of its last seconds so no word is cut in two. The speech engine's own VAD then
/// decides whether it holds speech.
///
/// Closed utterances are also grouped into refine windows of up to `windowLength`, cut between utterances: a decode
/// that sees 30 s of a quiet speaker at once hears noticeably more than one that starts cold at every pause. The levelled
/// audio is kept only from the oldest utterance not yet in a window.
public struct SpeechSegmenter {
    public static let pause: TimeInterval = 0.5
    public static let maxLength: TimeInterval = 15
    public static let minSpeech: TimeInterval = 0.2
    public static let padding: TimeInterval = 0.3
    public static let windowLength: TimeInterval = 30
    /// A track quiet this long (no utterance open) refines what it has without waiting for a full window.
    public static let idleWindow: TimeInterval = 8
    /// Levelled audio kept for windows at most; when refining falls this far behind, the oldest utterances keep their
    /// live text.
    static let maximumBacklog: TimeInterval = 300
    /// How far back from `maxLength` the cut may move to find a gap between words.
    static let cutWindow: TimeInterval = 3
    static let margin: Float = 6
    /// Nothing quieter than this (after levelling) is speech.
    static let quietest: Float = -60
    private static let block = 320  // 20 ms

    private var normalizer = LevelNormalizer()
    private var audio: [Float] = []   // levelled, from `audioStart`
    private var audioStart = 0
    private var waiting: [(id: UUID, start: Int, end: Int)] = []
    private var position = 0          // samples consumed so far
    private var pending: [Float] = [] // < one block, waiting for more samples
    private var current: [Float] = []
    private var levels: [Float] = []  // per block of `current`
    private var voicedBlocks: [Bool] = []
    private var currentStart = 0
    private var currentID = UUID()
    private var voiced = 0
    private var silentRun = 0
    private var history: [Float] = [] // the last `padding` of audio while idle, so a word's onset is kept
    private var floor: Float = -60

    /// `startSample` places the first sample on the recording's timeline (a recovered tail starts mid-recording).
    public init(startSample: Int = 0) {
        position = startSample
        audioStart = startSample
    }

    private static func samples(_ seconds: TimeInterval) -> Int { Int(seconds * Double(AudioClip.sampleRate)) }

    /// The gain the track is levelled with right now (dB).
    public var gain: Float { normalizer.currentGain }

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

    /// The utterance still being spoken, once it holds `minSpeech` of voiced audio (for a live partial; a copy).
    public var open: Utterance? {
        guard voiced >= Self.samples(Self.minSpeech) else { return nil }
        return Utterance(id: currentID, samples: current, start: Double(currentStart) / Double(AudioClip.sampleRate))
    }

    /// Id and length of `open` without copying its samples.
    public var openSpan: (id: UUID, length: TimeInterval)? {
        guard voiced >= Self.samples(Self.minSpeech) else { return nil }
        return (currentID, Double(current.count) / Double(AudioClip.sampleRate))
    }

    /// Closes whatever is open (end of recording, or a stop): the samples still waiting for a whole block count too.
    public mutating func flush() -> Utterance? {
        if !pending.isEmpty {
            let tail = normalizer.process(pending)
            audio += tail
            position += tail.count
            if !current.isEmpty { current += tail }
        }
        pending = []
        return close()
    }

    /// The next refine window: consecutive closed utterances spanning up to `windowLength`, once a later one no longer
    /// fits, or the track has been quiet for `idleWindow`, or with `force` (the end) whatever is closed.
    public mutating func window(force: Bool = false) -> RefineWindow? {
        guard let first = waiting.first else { return nil }
        var count = waiting.count
        if let over = waiting.firstIndex(where: { $0.end - first.start > Self.samples(Self.windowLength) }) {
            count = max(1, over)
        } else if !force {
            guard current.isEmpty, position - waiting[waiting.count - 1].end >= Self.samples(Self.idleWindow) else { return nil }
        }
        let taken = Array(waiting.prefix(count))
        waiting.removeFirst(count)
        defer { trimAudio() }
        let lower = max(taken[0].start, audioStart), upper = min(taken[taken.count - 1].end, audioStart + audio.count)
        guard upper > lower else { return nil }
        return RefineWindow(utteranceIDs: taken.map(\.id), samples: Array(audio[(lower - audioStart)..<(upper - audioStart)]),
                            start: Double(lower) / Double(AudioClip.sampleRate))
    }

    /// Drops levelled audio no window will need: before the oldest waiting utterance, the open one and the onset padding.
    /// Runs once a second's worth can go, so the copy is rare.
    private mutating func trimAudio() {
        let backlog = Self.samples(Self.maximumBacklog)
        while let oldest = waiting.first, position - oldest.start > backlog { waiting.removeFirst() }
        let needed = min(waiting.first?.start ?? .max, current.isEmpty ? position - Self.samples(Self.padding) : currentStart)
        let drop = min(audio.count, needed - audioStart)
        guard drop >= AudioClip.sampleRate else { return }
        audio.removeFirst(drop)
        audioStart += drop
    }

    private mutating func consume(_ raw: [Float]) -> Utterance? {
        defer { position += raw.count; trimAudio() }
        let block = normalizer.process(raw)
        audio += block
        let level = decibels(block[...])
        // Digital silence (a far end that went quiet, a muted microphone) says nothing about the room's noise.
        if level > -100 { floor = min(level, floor + 0.05) }
        let isVoiced = level > max(Self.quietest, floor + Self.margin)

        if current.isEmpty {
            guard isVoiced else {
                history = Array((history + block).suffix(Self.samples(Self.padding)))
                return nil
            }
            current = history + block
            levels = [Float](repeating: -120, count: history.count / Self.block) + [level]
            voicedBlocks = [Bool](repeating: false, count: levels.count - 1) + [true]
            currentStart = position - history.count
            currentID = UUID()
            history = []
            voiced = block.count
            silentRun = 0
            return nil
        }
        current += block
        levels.append(level)
        voicedBlocks.append(isVoiced)
        if isVoiced { voiced += block.count; silentRun = 0 } else { silentRun += block.count }
        if silentRun >= Self.samples(Self.pause) {
            // Keep a little of the trailing silence; the rest starts the next onset history.
            let trim = max(0, silentRun - Self.samples(Self.padding))
            history = Array(current.suffix(min(trim, Self.samples(Self.padding))))
            current.removeLast(trim)
            return close()
        }
        if current.count >= Self.samples(Self.maxLength) { return cut() }
        return nil
    }

    /// A monologue at `maxLength`: closes at the quietest block of its last `cutWindow` and keeps the rest open.
    private mutating func cut() -> Utterance? {
        let window = Self.samples(Self.cutWindow) / Self.block
        let first = max(1, levels.count - window)
        // The latest of the quietest blocks: a level stretch (one long vowel, a tone) still cuts at `maxLength`.
        let quietest = (first..<levels.count).reversed().min { levels[$0] < levels[$1] } ?? levels.count
        let split = min(current.count, quietest * Self.block)
        let rest = Array(current[split...]), restLevels = Array(levels[quietest...]), restVoiced = Array(voicedBlocks[quietest...])
        current = Array(current[..<split])
        voiced = voicedBlocks[..<quietest].filter { $0 }.count * Self.block
        let closed = close()
        current = rest
        levels = restLevels
        voicedBlocks = restVoiced
        currentStart += split
        currentID = UUID()
        voiced = restVoiced.filter { $0 }.count * Self.block
        silentRun = (restVoiced.lastIndex(of: true).map { restVoiced.count - 1 - $0 } ?? restVoiced.count) * Self.block
        return closed
    }

    private mutating func close() -> Utterance? {
        let start = currentStart
        defer { current = []; levels = []; voicedBlocks = []; voiced = 0; silentRun = 0 }
        guard voiced >= Self.samples(Self.minSpeech) else { return nil }
        waiting.append((currentID, start, start + current.count))
        return Utterance(id: currentID, samples: current, start: Double(start) / Double(AudioClip.sampleRate))
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

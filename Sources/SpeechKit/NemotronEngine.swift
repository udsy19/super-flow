import AVFoundation
import FluidAudio
import Foundation
import SuperFlowCore

/// NVIDIA Nemotron Speech Streaming EN 0.6B, 1120 ms chunks, via FluidAudio (stt-second-engine.md §5.3): a cache-aware
/// streaming RNNT on the ANE, loaded from the app's own `Models/asr/<id>` folder. Text grows while the key is held, so
/// key-up only has the last chunk left to decode. English only; no vocabulary biasing (the dictionary pass in CleanupKit
/// covers names).
public actor NemotronEngine {
    public let directory: URL
    private var manager: StreamingNemotronAsrManager?
    /// Silence fed before every stream: without it the model dropped the first word of 7 of 48 test clips.
    static let leadIn: TimeInterval = 0.4

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() async throws {
        let manager = StreamingNemotronAsrManager()
        try await manager.loadModels(from: directory)
        self.manager = manager
    }

    /// One second of silence end to end, so the ANE plans are built before the first dictation (the first load of a
    /// new install compiles for about 14 s; macOS caches it).
    public func warm() async {
        _ = try? await transcribe(AudioClip(samples: [Float](repeating: 0, count: AudioClip.sampleRate)))
    }

    public var isLoaded: Bool { manager != nil }

    /// Starts a stream: fresh state, then the lead-in.
    public func begin() async throws {
        let manager = try loaded()
        await manager.reset()
        _ = try await manager.process(audioBuffer: try Self.buffer([Float](repeating: 0, count: Int(Self.leadIn * Double(AudioClip.sampleRate)))))
    }

    /// Feeds audio; returns the text recognised so far (it changes once per 1.12 s chunk).
    public func append(_ samples: [Float]) async throws -> String {
        let manager = try loaded()
        if !samples.isEmpty { _ = try await manager.process(audioBuffer: try Self.buffer(samples)) }
        return await manager.getPartialTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ends the stream: decodes what is left (padded to a chunk) and returns the whole text.
    public func end() async throws -> String {
        try await loaded().finish().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One whole clip (Retry transcript, imports): a stream fed at once.
    public func transcribe(_ clip: AudioClip) async throws -> Transcript {
        try await begin()
        _ = try await append(clip.samples)
        let text = try await end()
        let segments = text.isEmpty ? [] : [TranscriptSegment(start: clip.startTime, end: clip.startTime + clip.duration, text: text)]
        return Transcript(text: text, language: "en", segments: segments)
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    private func loaded() throws -> StreamingNemotronAsrManager {
        guard let manager else { throw SpeechError.engineUnavailable("Nemotron isn't loaded.") }
        return manager
    }

    /// 16 kHz mono float samples as the PCM buffer FluidAudio takes.
    static func buffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioClip.sampleRate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let channel = buffer.floatChannelData?[0] else { throw SpeechError.failed("Couldn't prepare the audio for Nemotron.") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { if let base = $0.baseAddress { channel.update(from: base, count: samples.count) } }
        return buffer
    }
}

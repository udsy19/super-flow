@preconcurrency import AVFoundation
import Foundation
import Speech
import SuperFlowCore

/// Whether this Mac offers Apple's SpeechTranscriber (macOS 26 on supported hardware). Below macOS 26 the engine is
/// hidden; the app still builds and runs on macOS 14.
enum AppleSpeech {
    static var isSupported: Bool {
        if #available(macOS 26, *) { return SpeechTranscriber.isAvailable }
        return false
    }
}

/// Apple's on-device SpeechAnalyzer and SpeechTranscriber (stt-second-engine.md §6). macOS owns the model and shares it
/// between apps, so Super Flow downloads nothing; the first use of a language asks the OS to install its assets. One
/// locale per engine and no language detection, so it is used only for a single dictation language it supports.
@available(macOS 26, *)
public actor AppleSpeechEngine {
    public let locale: Locale

    public init(locale: Locale) {
        self.locale = locale
    }

    /// The supported locale for a BCP-47 language ("en" → en_US), or nil.
    public static func locale(for language: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language))
    }

    /// Makes sure the OS has the language's assets (a system download the first time the engine is chosen).
    public func load() async throws {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    public func warm() async {
        _ = try? await transcribe(AudioClip(samples: [Float](repeating: 0, count: AudioClip.sampleRate)), vocabulary: [])
    }

    /// Recognises one clip. `vocabulary` biases recognition toward the dictionary's words.
    public func transcribe(_ clip: AudioClip, vocabulary: [String]) async throws -> Transcript {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechError.engineUnavailable("Apple's speech model isn't available for \(locale.identifier).")
        }
        let input = try Self.buffer(clip.samples, in: format)
        let results = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal { text += String(result.text.characters) }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: input))
        continuation.finish()
        do {
            try await analyzer.start(inputSequence: stream)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            results.cancel()
            throw error
        }
        let text = try await results.value
        let language = locale.language.languageCode?.identifier ?? "en"
        let segments = text.isEmpty ? [] : [TranscriptSegment(start: clip.startTime, end: clip.startTime + clip.duration, text: text)]
        return Transcript(text: text, language: language, segments: segments)
    }

    /// 16 kHz mono float samples converted to the analyzer's format.
    static func buffer(_ samples: [Float], in format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioClip.sampleRate), channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let channel = input.floatChannelData?[0] else { throw SpeechError.failed("Couldn't prepare the audio.") }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { if let base = $0.baseAddress { channel.update(from: base, count: samples.count) } }
        if format == source { return input }
        guard let converter = AVAudioConverter(from: source, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / source.sampleRate) + 1024)
        else { throw SpeechError.failed("Couldn't convert the audio.") }
        var delivered = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, state in
            if delivered { state.pointee = .endOfStream; return nil }
            delivered = true
            state.pointee = .haveData
            return input
        }
        if status == .error { throw failure ?? SpeechError.failed("Couldn't convert the audio.") }
        return output
    }
}

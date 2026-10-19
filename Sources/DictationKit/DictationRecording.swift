import AVFoundation
import Foundation
import SuperFlowCore

/// A dictation's audio, on disk from the first frame (behaviour.md §2.3, §11.1), so a crash, a force quit or a full
/// battery never takes what the user said: 32-bit float samples are appended to `Audio/Dictations/<id>.pcm` as they
/// arrive, next to `<id>.json` (when, where and how it was dictated). A finished dictation turns them into `<id>.caf`
/// for playback and "Retry transcript", or deletes them; the next launch turns any left behind into History rows.
/// Nothing is written when the local data policy is "never store".
@MainActor
final class DictationRecording {
    struct Info: Codable, Equatable {
        var id: UUID
        var startedAt: Date
        var app: AppRecord?
        var mode: DictationMode
        var source: DictationSource
    }

    let info: Info
    private var handle: FileHandle?
    /// Held while recording, so another running copy's launch recovery leaves this file alone.
    private var lock: WriterLock?
    private(set) var sampleCount = 0

    private static var folder: URL { SuperFlowPaths.dictationAudio }
    private static func url(_ id: UUID, _ ext: String) -> URL { folder.appendingPathComponent("\(id.uuidString).\(ext)") }

    /// Starts the files; nil when they can't be created (a read-only or full disk): the dictation still runs.
    init?(_ info: Info) {
        self.info = info
        let fm = FileManager.default
        let pcm = Self.url(info.id, "pcm")
        guard let meta = try? JSON.encoder.encode(info), fm.createFile(atPath: pcm.path, contents: nil),
              (try? meta.write(to: Self.url(info.id, "json"), options: .atomic)) != nil,
              let handle = try? FileHandle(forWritingTo: pcm) else {
            Log.audio.error("Couldn't start the dictation's audio file; it won't survive a crash")
            try? fm.removeItem(at: pcm)
            return nil
        }
        self.handle = handle
        lock = WriterLock(pcm)
    }

    /// Appends samples straight to the file (the kernel keeps them even if the app dies the next moment). A write the
    /// disk refuses closes the file; what was written stays.
    func append(_ samples: [Float]) {
        guard let handle, !samples.isEmpty else { return }
        do {
            try handle.write(contentsOf: samples.withUnsafeBufferPointer { Data(buffer: $0) })
            sampleCount += samples.count
        } catch {
            Log.audio.error("Dictation audio stopped being saved: \(error.localizedDescription, privacy: .public)")
            try? handle.close()
            self.handle = nil
        }
    }

    var duration: TimeInterval { Double(sampleCount) / Double(AudioClip.sampleRate) }

    /// Ends the recording: `keep` turns it into `<id>.caf` and returns that file name; otherwise the audio is deleted.
    func finish(keep: Bool) -> String? {
        try? handle?.close()
        handle = nil
        lock?.release()
        lock = nil
        return Self.settle(info.id, keep: keep && sampleCount > 0)
    }

    // MARK: Files

    /// Converts `<id>.pcm` into `<id>.caf` (when `keep`) and removes the `.pcm` and `.json`; the caf's name, or nil.
    private static func settle(_ id: UUID, keep: Bool) -> String? {
        let fm = FileManager.default
        let pcm = url(id, "pcm"), caf = url(id, "caf")
        var kept: String?
        if keep {
            do {
                try convert(pcm, to: caf)
                kept = caf.lastPathComponent
            } catch {
                // The raw file stays for the next launch to try again; nothing is lost.
                Log.audio.error("Couldn't keep the dictation's audio: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        try? fm.removeItem(at: pcm)
        try? fm.removeItem(at: url(id, "json"))
        return kept
    }

    /// Streams the raw samples into a 16 kHz mono Float32 CAF, ten seconds at a time; the CAF only appears complete.
    private static func convert(_ pcm: URL, to caf: URL) throws {
        let reader = try FileHandle(forReadingFrom: pcm)
        defer { try? reader.close() }
        let partial = caf.deletingLastPathComponent().appendingPathComponent(caf.deletingPathExtension().lastPathComponent + ".partial.caf")
        try? FileManager.default.removeItem(at: partial)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioClip.sampleRate), channels: 1, interleaved: false)!
        do {
            let file = try AVAudioFile(forWriting: partial, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let block = 10 * AudioClip.sampleRate
            while let data = try reader.read(upToCount: block * 4), !data.isEmpty {
                let count = data.count / 4
                guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let channel = buffer.floatChannelData?[0] else { break }
                buffer.frameLength = AVAudioFrameCount(count)
                data.withUnsafeBytes { raw in channel.update(from: raw.bindMemory(to: Float.self).baseAddress!, count: count) }
                try file.write(from: buffer)
            }
        }
        guard rename(partial.path, caf.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    /// The samples of a kept dictation (`Dictation.audioFile`), for "Retry transcript"; nil when the file is gone.
    static func samples(of file: String) -> [Float]? {
        try? AudioClip.samples(of: folder.appendingPathComponent(file))
    }

    /// Recordings a crash, force quit or power loss left behind (not `except`, the one running now): each becomes a
    /// History row with its audio (when it holds more than a tap and History is kept), and its raw files go.
    static func recoverLeftovers(except running: UUID?) -> [Dictation] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        var recovered: [Dictation] = []
        for name in names where name.hasSuffix(".pcm") {
            guard let id = UUID(uuidString: String(name.dropLast(4))), id != running, !WriterLock.isHeld(url(id, "pcm")) else { continue }
            let info = (try? Data(contentsOf: url(id, "json"))).flatMap { try? JSON.decoder.decode(Info.self, from: $0) }
            let samples = ((try? fm.attributesOfItem(atPath: url(id, "pcm").path))?[.size] as? Int ?? 0) / 4
            let duration = Double(samples) / Double(AudioClip.sampleRate)
            let worthKeeping = duration >= DictationLimits.silentTapDuration && Defaults[.localDataPolicy] != .never
            guard worthKeeping, let file = settle(id, keep: true) else {
                if !worthKeeping { _ = settle(id, keep: false) }
                continue
            }
            let started = info?.startedAt ?? ((try? fm.attributesOfItem(atPath: url(id, "caf").path))?[.creationDate] as? Date) ?? Date()
            recovered.append(Dictation(id: id, createdAt: started, rawText: "", cleanedText: "", app: info?.app, duration: duration, wordCount: 0,
                                       mode: info?.mode ?? .pushToTalk, source: info?.source ?? .keyboard, outcome: .error, audioFile: file))
        }
        // A `.json` whose audio never started has nothing to recover.
        for name in names where name.hasSuffix(".json") {
            let base = String(name.dropLast(5))
            if !names.contains(base + ".pcm"), UUID(uuidString: base) != running { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
        }
        return recovered
    }
}

/// JSON for the recording's sidecar: dates as seconds, like the store.
private enum JSON {
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
}

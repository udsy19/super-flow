import AVFoundation
import Foundation
import SuperFlowCore

/// Dictation audio kept for retry and playback (behaviour.md §2.3, §11.1): `Audio/Dictations/<id>.caf`, 16 kHz mono
/// Float32, written after the dictation so the pipeline never waits on disk.
enum DictationAudioFile {
    static func write(_ samples: [Float], id: UUID) throws -> String {
        let name = "\(id.uuidString).caf"
        let url = SuperFlowPaths.dictationAudio.appendingPathComponent(name)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioClip.sampleRate), channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            throw AudioError.noAudio
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] { samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) } }
        try file.write(from: buffer)
        return name
    }
}

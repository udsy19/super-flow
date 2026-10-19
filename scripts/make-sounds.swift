#!/usr/bin/env swift
// Synthesises Super Flow's cue sounds (behaviour.md §17, `SoundCue`) into Resources/Sounds/<cue>.wav: short, quiet,
// sine-based tones with soft envelopes, designed here rather than taken from anywhere. 44.1 kHz mono 16-bit.
//
//   swift scripts/make-sounds.swift [Resources/Sounds]
import AVFoundation
import Foundation

let sampleRate = 44_100.0
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Sounds")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// One note: frequency, start, length (seconds) and peak amplitude, with a gentle attack and an exponential tail.
struct Note { var hz: Double; var at: Double; var length: Double; var level: Double = 0.18 }

func render(_ notes: [Note], duration: Double) -> [Float] {
    let count = Int(duration * sampleRate)
    var samples = [Float](repeating: 0, count: count)
    for note in notes {
        let start = Int(note.at * sampleRate), length = Int(note.length * sampleRate)
        for i in 0..<length where start + i < count {
            let t = Double(i) / sampleRate
            let attack = min(1, t / 0.008)
            let release = exp(-t / (note.length * 0.35))
            // A touch of the second harmonic keeps the tone from sounding like a pure beep.
            let wave = sin(2 * .pi * note.hz * t) + 0.18 * sin(4 * .pi * note.hz * t)
            samples[start + i] += Float(note.level * attack * release * wave)
        }
    }
    // A soft limiter so stacked notes never clip.
    return samples.map { max(-0.95, min(0.95, $0)) }
}

func write(_ name: String, _ samples: [Float]) throws {
    let url = output.appendingPathComponent("\(name).wav")
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    try file.write(from: buffer)
    print("wrote \(url.path) (\(String(format: "%.2f", Double(samples.count) / sampleRate)) s)")
}

// Start: a rising pair, the mic opening.
try write("dictationStart", render([Note(hz: 660, at: 0, length: 0.09), Note(hz: 880, at: 0.07, length: 0.14)], duration: 0.26))
// Stop: the same pair falling, a little softer.
try write("dictationStop", render([Note(hz: 880, at: 0, length: 0.09, level: 0.15), Note(hz: 660, at: 0.07, length: 0.16, level: 0.15)], duration: 0.28))
// Hands-free lock: a rising triplet that settles, "latched".
try write("handsFreeLock", render([Note(hz: 587, at: 0, length: 0.08), Note(hz: 784, at: 0.07, length: 0.08), Note(hz: 988, at: 0.14, length: 0.18)], duration: 0.36))
// Paste: one short, soft tick.
try write("paste", render([Note(hz: 1_320, at: 0, length: 0.06, level: 0.12)], duration: 0.12))
// Done / success: a major third, bright and brief.
try write("notificationSuccess", render([Note(hz: 784, at: 0, length: 0.12, level: 0.14), Note(hz: 988, at: 0.1, length: 0.2, level: 0.14)], duration: 0.34))
// Error: a low minor second, dull.
try write("notificationError", render([Note(hz: 311, at: 0, length: 0.14, level: 0.16), Note(hz: 294, at: 0.12, length: 0.22, level: 0.14)], duration: 0.38))
// Alert: two equal taps.
try write("notificationAlert", render([Note(hz: 740, at: 0, length: 0.07, level: 0.13), Note(hz: 740, at: 0.12, length: 0.1, level: 0.13)], duration: 0.26))
// Achievement / meeting saved: a slow arpeggio.
try write("achievement", render([Note(hz: 523, at: 0, length: 0.14, level: 0.13), Note(hz: 659, at: 0.11, length: 0.14, level: 0.13),
                                 Note(hz: 784, at: 0.22, length: 0.14, level: 0.13), Note(hz: 1_047, at: 0.33, length: 0.3, level: 0.13)], duration: 0.68))

import AVFoundation
import AudioKit
import SuperFlowCore

// Owned with AudioKit. Everything here runs on synthetic buffers and WAV files written to the temporary support
// folder: the self-test never opens the microphone, taps system audio, changes the output volume or plays a sound.
func registerAudioKitTests() {
    SelfTest.cases.append(("AudioKit.levelScaler", { audioLevelScaler() }))
    SelfTest.cases.append(("AudioKit.frameAssembler", { audioFrameAssembler() }))
    SelfTest.cases.append(("AudioKit.wavFixtureRoundTrip", { audioWavRoundTrip() }))
    SelfTest.cases.append(("AudioKit.frameHubAndPreRoll", { audioFrameHub() }))
    SelfTest.cases.append(("AudioKit.levelBatching", { audioLevelBatching() }))
    SelfTest.cases.append(("AudioKit.deviceChoice", { audioDeviceChoice() }))
    SelfTest.cases.append(("AudioKit.unpluggedMicFallsBack", { audioUnpluggedMicFallsBack() }))
    SelfTest.cases.append(("AudioKit.serviceWithoutCapture", { MainActor.assumeIsolated { audioServiceIdle() } }))
}

/// A sine wave as a PCM buffer in any layout the hardware might deliver.
func sineBuffer(frequency: Double, seconds: Double, sampleRate: Double, channels: AVAudioChannelCount, amplitude: Float = 0.5,
                interleaved: Bool = false) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: interleaved)!
    let frames = AVAudioFrameCount(seconds * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    for i in 0..<Int(frames) {
        let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        if interleaved {
            let data = list[0].mData!.assumingMemoryBound(to: Float.self)
            for c in 0..<Int(channels) { data[i * Int(channels) + c] = value }
        } else {
            for c in 0..<Int(channels) { list[c].mData!.assumingMemoryBound(to: Float.self)[i] = value }
        }
    }
    return buffer
}

/// Zero crossings per second / 2 ≈ the dominant frequency of a clean tone.
func estimatedFrequency(_ samples: [Float], sampleRate: Double) -> Double {
    var crossings = 0
    for i in 1..<samples.count where (samples[i - 1] < 0) != (samples[i] < 0) { crossings += 1 }
    return Double(crossings) / 2 / (Double(samples.count) / sampleRate)
}

private func audioLevelScaler() {
    var scaler = LevelScaler()
    check(scaler.level(rms: 1) == 0 && scaler.floor == 0, "the floor starts at 0 dB, so a full-scale first frame reads 0")
    _ = scaler.level(rms: 0.001)    // −60 dB: the floor follows it down
    check(abs(scaler.floor - -60) < 0.01, "the floor follows the quietest frame (\(scaler.floor))")
    _ = scaler.level(rms: 0)
    check(scaler.floor == LevelScaler.minimumFloor, "the floor never goes below −60 dB")
    check(abs(scaler.level(rms: 0.01) - 1) < 0.001, "20 dB above the floor is full level")
    check(abs(scaler.level(rms: 0.00316) - 0.5) < 0.01, "10 dB above the floor is half level")
    check(LevelScaler.rms([0.5, -0.5, 0.5, -0.5]) == 0.5 && LevelScaler.rms([]) == 0, "RMS")
}

private func audioFrameAssembler() {
    // 48 kHz stereo, the usual built-in format, in uneven buffer sizes.
    let assembler = FrameAssembler(channel: .mic)
    var frames: [AudioFrame] = []
    let tone = sineBuffer(frequency: 440, seconds: 1, sampleRate: 48_000, channels: 2)
    var offset: AVAudioFrameCount = 0
    var hostTime: TimeInterval? = 1000
    for size in [AVAudioFrameCount(1024), 512, 4096, 333, 9999, 48_000] where offset < tone.frameLength {
        let count = min(size, tone.frameLength - offset)
        let piece = AVAudioPCMBuffer(pcmFormat: tone.format, frameCapacity: count)!
        piece.frameLength = count
        for c in 0..<2 { memcpy(piece.floatChannelData![c], tone.floatChannelData![c] + Int(offset), Int(count) * 4) }
        frames += assembler.append(piece, hostTime: hostTime)
        hostTime = nil
        offset += count
    }
    let samples = frames.flatMap(\.samples)
    check(frames.allSatisfy { $0.samples.count == FrameAssembler.frameLength && $0.channel == .mic }, "every frame is 640 samples on the mic channel")
    check(samples.count >= 15_000 && samples.count <= 16_000, "1 s at 48 kHz becomes ~16 000 samples (\(samples.count))")
    check(abs(estimatedFrequency(Array(samples.dropFirst(800)), sampleRate: 16_000) - 440) < 10, "the tone survives resampling and downmix")
    let peak = samples.dropFirst(800).map(abs).max() ?? 0
    check(peak > 0.4 && peak < 0.6, "downmix keeps the amplitude of identical channels (\(peak))")
    check(frames.first.map { abs($0.time - 1000) < 0.001 } ?? false, "the first frame carries the host time")
    let steps = zip(frames.dropFirst(), frames).map { $0.time - $1.time }
    check(steps.allSatisfy { abs($0 - 0.04) < 1e-6 }, "frames are 40 ms apart")
    check(frames.dropFirst(2).allSatisfy { $0.level >= 0 && $0.level <= 1 }, "levels stay in 0…1")

    // 16 kHz mono passes through untouched; interleaved 44.1 kHz converts too.
    let direct = FrameAssembler(channel: .system)
    let mono = sineBuffer(frequency: 1000, seconds: 0.08, sampleRate: 16_000, channels: 1)
    let passed = direct.append(mono, hostTime: 5)
    check(passed.count == 2 && passed[0].samples == Array(UnsafeBufferPointer(start: mono.floatChannelData![0], count: 640))
          && passed[1].channel == .system, "16 kHz mono is framed without conversion")
    let interleaved = FrameAssembler(channel: .system)
    let out = interleaved.append(sineBuffer(frequency: 300, seconds: 0.5, sampleRate: 44_100, channels: 2, interleaved: true), hostTime: 0)
    check(out.count >= 11 && abs(estimatedFrequency(Array(out.flatMap(\.samples).dropFirst(400)), sampleRate: 16_000) - 300) < 10,
          "interleaved 44.1 kHz stereo converts")
    direct.reset()
    check(direct.append(sineBuffer(frequency: 1000, seconds: 0.03, sampleRate: 16_000, channels: 1), hostTime: 0).isEmpty,
          "a partial frame waits for more samples")
    let tail = direct.finish()
    check(tail.count == 1 && tail[0].samples.count == 640 && tail[0].samples.suffix(160).allSatisfy { $0 == 0 },
          "finish pads the last partial frame with silence")
    check(direct.finish().isEmpty, "finish resets")
}

private func audioWavRoundTrip() {
    // A WAV fixture written the way a recorder would (44.1 kHz stereo Int16) and read back through the pipeline.
    let url = SuperFlowPaths.support.appendingPathComponent("fixture-tone.wav")
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
    do {
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: sineBuffer(frequency: 523.25, seconds: 2, sampleRate: 44_100, channels: 2, amplitude: 0.3))
    } catch {
        check(false, "writing the WAV fixture: \(error)")
        return
    }
    guard let file = try? AVAudioFile(forReading: url),
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: buffer)) != nil else {
        check(false, "reading the WAV fixture back")
        return
    }
    let assembler = FrameAssembler(channel: .mic)
    let frames = assembler.append(buffer, hostTime: 0) + assembler.finish()
    let samples = frames.flatMap(\.samples)
    check(samples.count >= 32_000 && samples.count < 32_000 + 2 * FrameAssembler.frameLength,
          "two seconds of WAV become two seconds at 16 kHz once the converter is drained (\(samples.count))")
    check(zip(frames.dropFirst(), frames).allSatisfy { abs($0.time - $1.time - 0.04) < 1e-6 }, "the drained tail keeps the 40 ms grid")
    check(abs(estimatedFrequency(Array(samples.dropFirst(800)), sampleRate: 16_000) - 523.25) < 10, "C5 stays C5")
}

private func audioFrameHub() {
    let hub = FrameHub()
    let first = hub.stream()
    let second = hub.stream()
    check(hub.subscriberCount == 2, "two subscribers")
    let mic = (0..<20).map { AudioFrame(channel: .mic, samples: [Float(Double($0))], time: Double($0) * 0.04, level: 0) }
    let system = [AudioFrame(channel: .system, samples: [9], time: 0.8, level: 0)]
    hub.publish(mic)
    hub.publish(system)
    hub.finishAll()
    let collect: (AsyncStream<AudioFrame>) -> [AudioFrame] = { stream in
        let result = MainActor.assumeIsolated { complete(5) { var all: [AudioFrame] = []; for await f in stream { all.append(f) }; return all } }
        if case .success(let frames)? = result { return frames }
        return []
    }
    let a = collect(first), b = collect(second)
    check(a.count == 21 && b.count == 21, "every subscriber gets every frame (\(a.count), \(b.count))")
    check(a.map(\.time) == b.map(\.time) && a.last?.channel == .system, "in order, both channels")

    // A late subscriber starts with the last 300 ms of microphone audio (pre-roll), never system audio.
    let late = FrameHub()
    late.publish(mic)
    late.publish(system)
    let seeded = late.stream()
    late.finishAll()
    let preRoll = collect(seeded)
    let span = (preRoll.last?.time ?? 0) + 0.04 - (preRoll.first?.time ?? 0)
    check(preRoll.allSatisfy { $0.channel == .mic } && span >= DictationLimits.preRoll - 0.001 && span < DictationLimits.preRoll + 0.04,
          "pre-roll is the last \(DictationLimits.preRoll) s of mic frames (\(preRoll.count) frames, \(span) s)")
    late.clearHistory()
    let afterClear = late.stream()
    late.finishAll()
    check(collect(afterClear).isEmpty, "stopping the microphone forgets the pre-roll")
    check(late.subscriberCount == 0, "finished streams unsubscribe")
}

private func audioLevelBatching() {
    var batcher = LevelBatcher()
    var outputs: [Float] = []
    for i in 0..<15 {
        let frame = AudioFrame(channel: .mic, samples: [], time: Double(i) * 0.04, level: i < 4 ? 0.2 : 0.8)
        if let level = batcher.add(frame) { outputs.append(level) }
    }
    // 150 ms of 40 ms frames: a batch closes every 4th frame (160 ms of audio).
    check(outputs.count == 3, "a level every ~150 ms of audio (\(outputs.count))")
    check(abs((outputs.first ?? 0) - 0.2) < 0.001 && abs((outputs.last ?? 0) - 0.8) < 0.001, "batches are averages")
}

private func audioDeviceChoice() {
    let builtIn = AudioDevice(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", isBuiltIn: true)
    let lidClosed = AudioDevice(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", isBuiltIn: true,
                                unavailableReason: "Laptop lid is closed")
    let usb = AudioDevice(id: "usb-1", name: "Yeti")
    let airpods = AudioDevice(id: "bt-1", name: "AirPods")
    let loopback = AudioDevice(id: "virtual-1", name: "Loopback", isVirtual: true)
    let all = [builtIn, usb, airpods, loopback]
    check(InputDevices.choose(from: all, override: "usb-1", ranking: ["bt-1"], systemDefault: nil)?.id == "usb-1", "the override wins")
    check(InputDevices.choose(from: all, override: "gone", ranking: ["gone-too", "bt-1", "usb-1"], systemDefault: nil)?.id == "bt-1",
          "then the first ranked device that is present")
    check(InputDevices.choose(from: all, override: nil, ranking: [], systemDefault: "usb-1")?.id == builtIn.id, "then the built-in mic")
    check(InputDevices.choose(from: [lidClosed, usb, loopback], override: lidClosed.id, ranking: [], systemDefault: "virtual-1")?.id == "virtual-1",
          "an unavailable device is skipped; then the system default")
    check(InputDevices.choose(from: [lidClosed, loopback, usb], override: nil, ranking: [], systemDefault: nil)?.id == "usb-1",
          "then any real device before a virtual one")
    check(InputDevices.choose(from: [lidClosed], override: nil, ranking: [], systemDefault: nil) == nil, "nothing usable")
}

@MainActor private func audioServiceIdle() {
    // Reads the device list (no capture) and checks the idle state; nothing is started.
    let audio = AudioCapture.shared
    check(!audio.isCapturingMicrophone && !audio.isCapturingSystemAudio, "nothing captures until asked")
    let expected: SystemAudioMethod = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 4, patchVersion: 0))
        ? .processTap : .screenCaptureKit
    check(audio.systemAudioMethod == expected, "process tap on macOS 14.4+, ScreenCaptureKit before")
    check(Set(audio.devices.map(\.id)).count == audio.devices.count, "device ids are unique")
    if let selected = audio.selectedDevice { check(selected.unavailableReason == nil, "the selected microphone is usable") }
    print("  audio: \(audio.devices.count) input device(s), selected \(audio.selectedDevice?.name ?? "none")")
    // Muting is gated by the setting (off by default), so this must not touch the output device.
    audio.muteOutput()
    audio.unmuteOutput()
    audio.stopMicrophone()   // unbalanced stop is harmless
    check(!audio.isCapturingMicrophone, "an unbalanced stop keeps the microphone off")
    var levels: [Float] = []
    let cancellable = audio.level.sink { levels.append($0) }
    check(levels == [0], "the level starts at 0")
    cancellable.cancel()
}

/// The chosen microphone was unplugged (or won't restart after a format change): capture moves to the system default
/// input instead of going silent; only when nothing starts is the chosen device's error reported.
private func audioUnpluggedMicFallsBack() {
    struct Gone: Error {}
    var tried: [Int?] = []
    let started = try? InputDevices.startWithFallback(7) { (id: Int?) in
        tried.append(id)
        if id == 7 { throw AudioError.deviceUnavailable("USB mic") }
    }
    check(tried == [7, nil] && started == .some(nil), "the default input takes over: \(tried)")
    tried = []
    check((try? InputDevices.startWithFallback(7) { (id: Int?) in tried.append(id) }) == .some(7) && tried == [7], "a working device is used as is")
    tried = []
    do {
        _ = try InputDevices.startWithFallback(7) { (id: Int?) in tried.append(id); throw id == nil ? Gone() : AudioError.deviceUnavailable("USB mic") }
        check(false, "nothing starts: an error")
    } catch {
        check(error as? AudioError == .deviceUnavailable("USB mic") && tried == [7, nil], "the chosen device's error is reported")
    }
    tried = []
    check((try? InputDevices.startWithFallback(Int?.none) { (id: Int?) in tried.append(id); throw Gone() }) == nil && tried == [nil],
          "the default input isn't tried twice")
}

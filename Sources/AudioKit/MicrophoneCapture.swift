import AudioToolbox
import AVFoundation
import SuperFlowCore

/// The microphone through `AVAudioEngine` (behaviour.md §4.2): an input tap on the chosen device whose buffers go
/// straight into a `FrameAssembler`. The engine is created on start and torn down on stop, so the microphone (and the
/// orange privacy dot) is only on while something is listening.
final class MicrophoneCapture {
    private var engine: AVAudioEngine?
    private var deviceID: AudioObjectID?
    private var configurationObserver: NSObjectProtocol?
    private let assembler = FrameAssembler(channel: .mic)
    private let onFrames: ([AudioFrame]) -> Void

    init(onFrames: @escaping ([AudioFrame]) -> Void) {
        self.onFrames = onFrames
    }

    var isRunning: Bool { engine?.isRunning ?? false }

    /// Starts the tap on `device` (nil: the system default input), falling back to the system default when the device
    /// won't start. Throws `AudioError.deviceUnavailable` when no input starts.
    func start(device: AudioDevice?) throws {
        stop()
        let id = device.flatMap { CoreAudioHAL.device(withUID: $0.id) }
        let name = device?.name ?? "The microphone"
        _ = try InputDevices.startWithFallback(id) { try startEngine(deviceID: $0, name: name) }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
            // The device's format or route changed (AirPods connecting, sample-rate switch, the device going away):
            // rebuild the tap, on the system default input if the device itself won't come back.
            guard let self, let engine = self.engine, note.object as? AVAudioEngine === engine else { return }
            Log.audio.info("Microphone configuration changed; restarting the tap")
            do { _ = try InputDevices.startWithFallback(self.deviceID) { try self.startEngine(deviceID: $0, name: name) } } catch {
                Log.audio.error("The microphone couldn't be restarted: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        // The converter's last few milliseconds belong to the post-roll.
        onFrames(assembler.finish())
    }

    private func startEngine(deviceID: AudioObjectID?, name: String) throws {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        assembler.reset()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceID, let unit = input.audioUnit {
            var id = deviceID
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
                                              UInt32(MemoryLayout<AudioObjectID>.size))
            if status != noErr { Log.audio.error("Couldn't select input device \(deviceID): \(status)") }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.deviceUnavailable(name) }
        // ~20 ms at 48 kHz; the engine may round it, which only changes how often the tap fires.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [assembler, onFrames] buffer, time in
            onFrames(assembler.append(buffer, hostTime: time.hostSeconds))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Log.audio.error("Microphone engine failed: \(error.localizedDescription, privacy: .public)")
            throw AudioError.deviceUnavailable(name)
        }
        self.engine = engine
        self.deviceID = deviceID
        Log.audio.info("Microphone started: \(name, privacy: .public) \(format.sampleRate) Hz × \(format.channelCount)")
    }
}

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
    /// The tap's format, to tell a real change from the notification an engine posts while it settles after starting.
    private var tapFormat: (sampleRate: Double, channels: AVAudioChannelCount)?
    /// Rebuilds in the last couple of seconds; a device that keeps changing must not restart the tap forever.
    private var recentRebuilds: [Date] = []
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
            self.handleConfigurationChange(engine, name: name)
        }
    }

    /// The engine stops itself when its configuration changes. Starting an engine on the built-in microphone posts
    /// such a change too (the device settles), so the tap is only rebuilt when the format really changed or the engine
    /// won't simply start again; otherwise rebuilding posts the next change and the tap never gets any audio.
    private func handleConfigurationChange(_ engine: AVAudioEngine, name: String) {
        guard !engine.isRunning else { return }
        let format = engine.inputNode.outputFormat(forBus: 0)
        if let tapFormat, format.sampleRate == tapFormat.sampleRate, format.channelCount == tapFormat.channels {
            do {
                try engine.start()
                Log.audio.info("Microphone resumed after a configuration change")
                return
            } catch {
                Log.audio.error("Microphone didn't resume: \(error.localizedDescription, privacy: .public)")
            }
        }
        let now = Date()
        recentRebuilds = recentRebuilds.filter { now.timeIntervalSince($0) < 2 } + [now]
        guard recentRebuilds.count <= 3 else {
            Log.audio.error("Microphone keeps changing; not restarting the tap again")
            return
        }
        Log.audio.info("Microphone configuration changed; restarting the tap")
        do { _ = try InputDevices.startWithFallback(deviceID) { try startEngine(deviceID: $0, name: name) } } catch {
            Log.audio.error("The microphone couldn't be restarted: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        recentRebuilds = []
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
        tapFormat = (format.sampleRate, format.channelCount)
        Log.audio.info("Microphone started: \(name, privacy: .public) \(format.sampleRate) Hz × \(format.channelCount)")
    }
}

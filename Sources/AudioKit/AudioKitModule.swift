import Combine
import CoreAudio
import Foundation
import SuperFlowCore

/// Registers this module's service in `Services` (called once at launch).
public enum AudioKitModule {
    @MainActor public static func install() {
        Services.audio = AudioCapture.shared
    }
}

/// Microphone and system-audio capture (behaviour.md §4, §20.4; local-models.md §8.2, §9.1). Every capture becomes
/// 40 ms frames of 16 kHz mono on the host clock; `frames` hands each subscriber its own stream. The microphone is
/// reference-counted: dictation and a running meeting can both hold it, and it stops when the last one lets go.
/// Post-roll is the caller's: keep reading for `DictationLimits.postRoll` after key-up, then call `stopMicrophone()`.
@MainActor
public final class AudioCapture: AudioCapturing {
    public static let shared = AudioCapture()

    private let hub = FrameHub()
    private let levelSubject = CurrentValueSubject<Float, Never>(0)
    private let devicesSubject = CurrentValueSubject<[AudioDevice], Never>([])
    private let meter: MicLevelMeter
    private lazy var microphone = MicrophoneCapture { [hub, meter] frames in
        hub.publish(frames)
        meter.add(frames)
    }
    private lazy var system = SystemAudioCapture { [hub] frames in hub.publish(frames) }
    private let muter = OutputMuter()
    private let cues = CuePlayer()
    private var microphoneHolders = 0
    private var microphoneDeviceID: String?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public private(set) var devices: [AudioDevice] = [] { didSet { devicesSubject.send(devices) } }
    public private(set) var isCapturingMicrophone = false
    public private(set) var isCapturingSystemAudio = false

    init() {
        let subject = levelSubject
        meter = MicLevelMeter { level in DispatchQueue.main.async { subject.send(level) } }
        devices = InputDevices.current()
        devicesSubject.send(devices)   // property observers are silent inside init
        observeDevices()
    }

    public var selectedDevice: AudioDevice? {
        InputDevices.choose(from: devices, override: Defaults[.overrideAudioDeviceId], ranking: Defaults[.rankedAudioDevices],
                            systemDefault: CoreAudioHAL.defaultInputDevice.flatMap(CoreAudioHAL.uid))
    }

    public var systemAudioMethod: SystemAudioMethod { SystemAudioCapture.method }

    public var frames: AsyncStream<AudioFrame> { hub.stream() }

    public var level: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    public var deviceChanges: AnyPublisher<[AudioDevice], Never> { devicesSubject.eraseToAnyPublisher() }

    // MARK: Microphone

    public func startMicrophone() async throws {
        microphoneHolders += 1
        guard !isCapturingMicrophone else { return }
        do {
            try await Self.ensureMicrophonePermission()
            guard microphoneHolders > 0, !isCapturingMicrophone else { return }
            let device = selectedDevice
            try microphone.start(device: device)
            microphoneDeviceID = device?.id
            isCapturingMicrophone = true
        } catch {
            microphoneHolders = max(0, microphoneHolders - 1)
            throw error
        }
    }

    public func stopMicrophone() {
        microphoneHolders = max(0, microphoneHolders - 1)
        guard microphoneHolders == 0, isCapturingMicrophone else { return }
        microphone.stop()
        hub.clearHistory()
        meter.reset()
        isCapturingMicrophone = false
        microphoneDeviceID = nil
        levelSubject.send(0)
    }

    private static func ensureMicrophonePermission() async throws {
        switch Permissions.microphone {
        case .authorized: return
        case .notDetermined:
            if await Permissions.requestMicrophone() { return }
            throw AudioError.permissionDenied
        default:
            throw AudioError.permissionDenied
        }
    }

    // MARK: System audio

    public func startSystemAudio() async throws {
        guard !isCapturingSystemAudio else { return }
        try await system.start()
        isCapturingSystemAudio = true
    }

    public func stopSystemAudio() {
        guard isCapturingSystemAudio else { return }
        system.stop()
        isCapturingSystemAudio = false
    }

    // MARK: Output and cues

    public func muteOutput() {
        guard Defaults[.shouldMuteAudio] else { return }
        muter.mute()
    }

    public func unmuteOutput() {
        muter.unmute()
    }

    public func play(_ cue: SoundCue) {
        cues.play(cue)
    }

    // MARK: Device changes

    /// Refreshes the device list when devices come and go or the default input changes, and moves a running microphone
    /// to the new choice when its device disappeared or the preference now points elsewhere.
    private func observeDevices() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            let address = CoreAudioHAL.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.devicesChanged() }
            }
            var mutableAddress = address
            if AudioObjectAddPropertyListenerBlock(CoreAudioHAL.system, &mutableAddress, .main, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    private func devicesChanged() {
        devices = InputDevices.current()
        guard isCapturingMicrophone, let wanted = selectedDevice, wanted.id != microphoneDeviceID else { return }
        Log.audio.info("Switching microphone to \(wanted.name, privacy: .public)")
        do {
            try microphone.start(device: wanted)
            microphoneDeviceID = wanted.id
        } catch {
            Log.audio.error("Couldn't switch microphone: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Batches microphone levels for the Flow Bar (150 ms averages). Fed only from the microphone tap's thread.
final class MicLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var batcher = LevelBatcher()
    private let send: (Float) -> Void

    init(send: @escaping (Float) -> Void) {
        self.send = send
    }

    func add(_ frames: [AudioFrame]) {
        let levels: [Float] = lock.withLock { frames.compactMap { batcher.add($0) } }
        levels.forEach(send)
    }

    func reset() {
        lock.withLock { batcher.reset() }
    }
}

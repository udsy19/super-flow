import AppKit
import CoreAudio
import SuperFlowCore

/// "Mute all audio while dictating" (behaviour.md §4.6): mutes the default output device, or sets its volume to zero
/// when it has no mute control, and remembers what it owes so the restore reaches the same device even if the default
/// output changed in between.
final class OutputMuter {
    private enum Owed {
        case mute(device: AudioObjectID)
        case volume(device: AudioObjectID, element: AudioObjectPropertyElement, previous: Float32)
    }

    private var owed: [Owed] = []

    var isMuted: Bool { !owed.isEmpty }

    func mute() {
        guard owed.isEmpty, let device = CoreAudioHAL.defaultOutputDevice else { return }
        let muteAddress = CoreAudioHAL.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        if CoreAudioHAL.isSettable(device, muteAddress) {
            if CoreAudioHAL.value(device, muteAddress, initial: UInt32(0)) == 0, CoreAudioHAL.set(device, muteAddress, UInt32(1)) {
                owed = [.mute(device: device)]
            }
            return
        }
        // No master mute: zero each settable volume control (master, else the channels).
        for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
            let address = CoreAudioHAL.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            guard CoreAudioHAL.isSettable(device, address),
                  let previous = CoreAudioHAL.value(device, address, initial: Float32(0)), previous > 0,
                  CoreAudioHAL.set(device, address, Float32(0)) else { continue }
            owed.append(.volume(device: device, element: element, previous: previous))
            if element == kAudioObjectPropertyElementMain { break }
        }
    }

    func unmute() {
        for item in owed {
            switch item {
            case .mute(let device):
                CoreAudioHAL.set(device, CoreAudioHAL.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput), UInt32(0))
            case .volume(let device, let element, let previous):
                CoreAudioHAL.set(device, CoreAudioHAL.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                                                             element: element), previous)
            }
        }
        owed = []
    }
}

/// Cue sounds (behaviour.md §17, ui-reference.md §8): `Sounds/<cue>.wav` from the app bundle, dictation cues at full
/// volume and notification cues at half, only while "Dictation and notification sounds" is on. The sound files are
/// design assets; a cue whose file is missing stays silent.
@MainActor
final class CuePlayer {
    private var cache: [SoundCue: NSSound] = [:]
    private var missing: Set<SoundCue> = []
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    static func volume(for cue: SoundCue) -> Float {
        switch cue {
        case .notificationSuccess, .notificationError, .notificationAlert, .achievement: 0.5
        case .dictationStart, .dictationStop, .handsFreeLock, .paste: 1.0
        }
    }

    func play(_ cue: SoundCue) {
        guard Defaults[.enableSounds], let sound = sound(for: cue) else { return }
        sound.stop()
        sound.volume = CuePlayer.volume(for: cue)
        sound.play()
    }

    func sound(for cue: SoundCue) -> NSSound? {
        if let cached = cache[cue] { return cached }
        guard !missing.contains(cue) else { return nil }
        guard let url = bundle.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            missing.insert(cue)
            Log.audio.info("No sound file for cue \(cue.rawValue, privacy: .public)")
            return nil
        }
        cache[cue] = sound
        return sound
    }
}

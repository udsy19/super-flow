import Combine
import Foundation
import SuperFlowCore

/// Registers this module's service in `Services` (called once at launch).
public enum AudioKitModule {
    @MainActor public static func install() {
        Services.audio = AudioCapture.shared
    }
}

/// Placeholder capture service (behaviour.md §4, §20.4): reports no devices and throws on start until the
/// AVAudioEngine microphone path and the Core Audio process tap are built. Nothing here opens the microphone.
@MainActor
final class AudioCapture: AudioCapturing {
    static let shared = AudioCapture()
    private let levelSubject = CurrentValueSubject<Float, Never>(0)
    private var frameContinuation: AsyncStream<AudioFrame>.Continuation?
    private(set) lazy var frames: AsyncStream<AudioFrame> = AsyncStream { self.frameContinuation = $0 }

    var devices: [AudioDevice] { [] }
    var selectedDevice: AudioDevice? { nil }
    private(set) var isCapturingMicrophone = false
    private(set) var isCapturingSystemAudio = false
    var systemAudioMethod: SystemAudioMethod {
        if #available(macOS 14.4, *) { return .processTap }
        return .screenCaptureKit
    }

    func startMicrophone() async throws { throw AudioError.deviceUnavailable("Microphone capture isn't available yet") }
    func stopMicrophone() { isCapturingMicrophone = false }
    func startSystemAudio() async throws { throw AudioError.systemAudioUnsupported }
    func stopSystemAudio() { isCapturingSystemAudio = false }
    var level: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }
    func muteOutput() {}
    func unmuteOutput() {}
    func play(_ cue: SoundCue) {}
}

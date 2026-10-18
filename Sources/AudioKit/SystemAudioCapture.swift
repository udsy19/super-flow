import AVFoundation
import CoreAudio
import CoreMedia
import ScreenCaptureKit
import SuperFlowCore

/// The Mac's output for meetings, kept as its own "Them" channel (behaviour.md §20.4.2): a Core Audio process tap on
/// macOS 14.4+ ("System Audio Recording Only" permission), else ScreenCaptureKit audio (Screen Recording permission).
/// Our own process is excluded, so cue sounds never land in the transcript.
final class SystemAudioCapture {
    static var method: SystemAudioMethod {
        if #available(macOS 14.4, *) { return .processTap }
        return .screenCaptureKit
    }

    private let onFrames: ([AudioFrame]) -> Void
    private var tap: AnyObject?
    private var screenCapture: ScreenCaptureAudio?

    init(onFrames: @escaping ([AudioFrame]) -> Void) {
        self.onFrames = onFrames
    }

    var isRunning: Bool { tap != nil || screenCapture != nil }

    func start() async throws {
        stop()
        if #available(macOS 14.4, *) {
            let tap = ProcessTapCapture(onFrames: onFrames)
            try tap.start()
            self.tap = tap
        } else {
            let capture = ScreenCaptureAudio(onFrames: onFrames)
            try await capture.start()
            screenCapture = capture
        }
    }

    func stop() {
        if #available(macOS 14.4, *), let tap = tap as? ProcessTapCapture { tap.stop() }
        tap = nil
        screenCapture?.stop()
        screenCapture = nil
    }
}

/// A global stereo tap that excludes this process, read through a private aggregate device with drift compensation
/// (the pattern from AudioCap, BSD-2, and BetterWispr, Apache-2.0; oss-survey.md §5).
@available(macOS 14.4, *)
private final class ProcessTapCapture {
    private let onFrames: ([AudioFrame]) -> Void
    private let assembler = FrameAssembler(channel: .system)
    private let queue = DispatchQueue(label: "com.udsy.superflow.audio.system-tap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init(onFrames: @escaping ([AudioFrame]) -> Void) {
        self.onFrames = onFrames
    }

    func start() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcessObject.map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "Super Flow meeting audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != kAudioObjectUnknown else {
            throw AudioError.systemAudioUnsupported
        }
        tapID = tap
        do {
            try startAggregate(tapUUID: description.uuid.uuidString)
        } catch {
            stop()
            throw error
        }
        Log.audio.info("System audio tap started")
    }

    private func startAggregate(tapUUID: String) throws {
        guard var description = CoreAudioHAL.value(tapID, CoreAudioHAL.address(kAudioTapPropertyFormat), initial: AudioStreamBasicDescription()),
              let format = AVAudioFormat(streamDescription: &description),
              let output = CoreAudioHAL.defaultOutputDevice, let outputUID = CoreAudioHAL.uid(output) else {
            throw AudioError.systemAudioUnsupported
        }
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Super Flow Meeting Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUUID]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate) == noErr else {
            throw AudioError.systemAudioUnsupported
        }
        aggregateID = aggregate
        let expectedBuffers = format.isInterleaved ? 1 : Int(format.channelCount)
        let bytesPerFrame = Int(description.mBytesPerFrame)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) { [assembler, onFrames] _, input, inputTime, _, _ in
            // The tap's buffers come last when the output device also has inputs (a USB headset).
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard list.count >= expectedBuffers, bytesPerFrame > 0 else { return }
            let first = list.count - expectedBuffers
            let frames = AVAudioFrameCount(Int(list[first].mDataByteSize) / bytesPerFrame)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            buffer.frameLength = frames
            let target = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for i in 0..<expectedBuffers {
                guard let source = list[first + i].mData, let destination = target[i].mData else { return }
                memcpy(destination, source, min(Int(list[first + i].mDataByteSize), Int(target[i].mDataByteSize)))
            }
            let time = inputTime.pointee
            let host = time.mFlags.contains(.hostTimeValid) ? AVAudioTime.seconds(forHostTime: time.mHostTime) : nil
            onFrames(assembler.append(buffer, hostTime: host))
        }
        guard status == noErr, let procID else { throw AudioError.systemAudioUnsupported }
        guard AudioDeviceStart(aggregate, procID) == noErr else { throw AudioError.systemAudioUnsupported }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        assembler.reset()
    }

    /// This process as a Core Audio process object, so the tap leaves our own sounds out.
    private var ownProcessObject: AudioObjectID? {
        var address = CoreAudioHAL.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(CoreAudioHAL.system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }
}

/// ScreenCaptureKit audio for macOS 14.0–14.3 (needs Screen Recording). Video is configured as small and slow as
/// possible; only the audio output is consumed.
private final class ScreenCaptureAudio: NSObject, SCStreamOutput, SCStreamDelegate {
    private let onFrames: ([AudioFrame]) -> Void
    private let assembler = FrameAssembler(channel: .system)
    private let queue = DispatchQueue(label: "com.udsy.superflow.audio.screen-capture", qos: .userInitiated)
    private var stream: SCStream?

    init(onFrames: @escaping ([AudioFrame]) -> Void) {
        self.onFrames = onFrames
    }

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            Log.audio.error("ScreenCaptureKit unavailable: \(error.localizedDescription, privacy: .public)")
            throw AudioError.systemAudioUnsupported
        }
        guard let display = content.displays.first else { throw AudioError.systemAudioUnsupported }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []),
                              configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        Log.audio.info("System audio via ScreenCaptureKit started")
    }

    func stop() {
        let stream = stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
        queue.async { [assembler] in assembler.reset() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let buffer = Self.pcmBuffer(sampleBuffer) else { return }
        let time = sampleBuffer.presentationTimeStamp
        onFrames(assembler.append(buffer, hostTime: time.isValid ? time.seconds : nil))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.audio.error("ScreenCaptureKit stopped: \(error.localizedDescription, privacy: .public)")
    }

    private static func pcmBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        var asbd = basic.pointee
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let format = AVAudioFormat(streamDescription: &asbd),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                   into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}

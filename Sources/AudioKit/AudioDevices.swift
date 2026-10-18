import CoreAudio
import Foundation
import IOKit
import SuperFlowCore

/// Thin Core Audio HAL helpers: device lists, names, UIDs, transport types and the default devices.
enum CoreAudioHAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func value<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    @discardableResult
    static func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ newValue: T) -> Bool {
        var address = address
        var value = newValue
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafePointer(to: &value) { AudioObjectSetPropertyData(object, &address, 0, nil, size, $0) } == noErr
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address) else { return false }
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func objectIDs(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static var deviceIDs: [AudioObjectID] { objectIDs(system, address(kAudioHardwarePropertyDevices)) }

    static var defaultInputDevice: AudioObjectID? {
        value(system, address(kAudioHardwarePropertyDefaultInputDevice), initial: AudioObjectID(0)).flatMap { $0 == 0 ? nil : $0 }
    }

    static var defaultOutputDevice: AudioObjectID? {
        value(system, address(kAudioHardwarePropertyDefaultOutputDevice), initial: AudioObjectID(0)).flatMap { $0 == 0 ? nil : $0 }
    }

    static func uid(_ device: AudioObjectID) -> String? { string(device, kAudioDevicePropertyDeviceUID) }
    static func name(_ device: AudioObjectID) -> String? { string(device, kAudioObjectPropertyName) }

    static func transportType(_ device: AudioObjectID) -> UInt32 {
        value(device, address(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0
    }

    static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func device(withUID uid: String) -> AudioObjectID? {
        deviceIDs.first { self.uid($0) == uid }
    }

    /// Whether the built-in display's lid is closed (clamshell), which makes the built-in microphone unusable.
    static var isClamshellClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }
}

/// The microphones the user can pick (behaviour.md §4.1) and the rule that picks one.
public enum InputDevices {
    /// Every device with input channels, built-in first, then by name.
    static func current() -> [AudioDevice] {
        let clamshell = CoreAudioHAL.isClamshellClosed
        return CoreAudioHAL.deviceIDs.compactMap { id -> AudioDevice? in
            guard CoreAudioHAL.channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0,
                  let uid = CoreAudioHAL.uid(id) else { return nil }
            let transport = CoreAudioHAL.transportType(id)
            let builtIn = transport == kAudioDeviceTransportTypeBuiltIn
            let virtual = [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                           kAudioDeviceTransportTypeAutoAggregate, kAudioDeviceTransportTypeUnknown].contains(transport)
            return AudioDevice(id: uid, name: CoreAudioHAL.name(id) ?? uid, isBuiltIn: builtIn, isVirtual: virtual,
                               unavailableReason: builtIn && clamshell ? "Laptop lid is closed" : nil)
        }
        .sorted { ($0.isBuiltIn ? 0 : 1, $0.name) < ($1.isBuiltIn ? 0 : 1, $1.name) }
    }

    /// The device dictation uses: the override, else the highest-ranked usable device, else the built-in mic, else the
    /// system default, else any usable device.
    public static func choose(from devices: [AudioDevice], override: String?, ranking: [String], systemDefault: String?) -> AudioDevice? {
        let usable = devices.filter { $0.unavailableReason == nil }
        if let override, let device = usable.first(where: { $0.id == override }) { return device }
        for id in ranking {
            if let device = usable.first(where: { $0.id == id }) { return device }
        }
        if let builtIn = usable.first(where: \.isBuiltIn) { return builtIn }
        if let systemDefault, let device = usable.first(where: { $0.id == systemDefault }) { return device }
        return usable.first { !$0.isVirtual } ?? usable.first
    }
}

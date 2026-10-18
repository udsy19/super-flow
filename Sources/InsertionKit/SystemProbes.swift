import AppKit
import Carbon.HIToolbox
import IOKit
import IOKit.hid

/// Secure Keyboard Entry (behaviour.md §3.3.11, §9.8): while any app has it on, event taps receive no keys. The
/// owner's pid is published in the console user's IORegistry entry.
enum SecureInput {
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    static func ownerPID() -> pid_t? {
        guard isEnabled else { return nil }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        return users.lazy.compactMap { ($0["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value }.first
    }

    static func ownerBundleID() -> String? {
        ownerPID().flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    }

    /// The frontmost app turned it on itself: a password prompt, even where Accessibility shows no secure field.
    @MainActor static var isHeldByFrontmostApp: Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        return FieldRules.isSecure(role: nil, subrole: nil, secureInputOwner: ownerPID(), targetPID: pid)
    }
}

/// Whether a keyboard with an Fn/Globe key is connected (behaviour.md §3.1): Apple keyboards have one, built-in or
/// external (USB vendor 0x05AC, Bluetooth 0x004C); others are assumed not to.
public enum FnKeyboard {
    public struct Keyboard: Equatable, Sendable {
        public var vendorID: Int
        public var isBuiltIn: Bool
        public init(vendorID: Int, isBuiltIn: Bool) { self.vendorID = vendorID; self.isBuiltIn = isBuiltIn }
    }

    public static let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]

    public static func hasFnKey(_ keyboards: [Keyboard]) -> Bool {
        keyboards.contains { $0.isBuiltIn || appleVendorIDs.contains($0.vendorID) }
    }

    /// Connected HID keyboards, read from the IORegistry (no device is opened, so no Input Monitoring prompt).
    static func connected() -> [Keyboard] {
        guard let matching = IOServiceMatching(kIOHIDDeviceKey) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        func property(_ service: io_object_t, _ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        var keyboards: [Keyboard] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard (property(service, kIOHIDPrimaryUsagePageKey) as? Int) == kHIDPage_GenericDesktop,
                  (property(service, kIOHIDPrimaryUsageKey) as? Int) == kHIDUsage_GD_Keyboard else { continue }
            keyboards.append(Keyboard(vendorID: property(service, kIOHIDVendorIDKey) as? Int ?? 0,
                                      isBuiltIn: property(service, kIOHIDBuiltInKey) as? Bool ?? false))
        }
        return keyboards
    }
}

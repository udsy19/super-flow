import AppKit
import ApplicationServices
import AVFoundation
import os

public enum Log {
    public static let app = Logger(subsystem: SuperFlowPaths.bundleID, category: "app")
    public static let store = Logger(subsystem: SuperFlowPaths.bundleID, category: "store")
    public static let audio = Logger(subsystem: SuperFlowPaths.bundleID, category: "audio")
    public static let speech = Logger(subsystem: SuperFlowPaths.bundleID, category: "speech")
    public static let models = Logger(subsystem: SuperFlowPaths.bundleID, category: "models")
    public static let cleanup = Logger(subsystem: SuperFlowPaths.bundleID, category: "cleanup")
    public static let insertion = Logger(subsystem: SuperFlowPaths.bundleID, category: "insertion")
    public static let hotkeys = Logger(subsystem: SuperFlowPaths.bundleID, category: "hotkeys")
    public static let bar = Logger(subsystem: SuperFlowPaths.bundleID, category: "bar")
    public static let hub = Logger(subsystem: SuperFlowPaths.bundleID, category: "hub")
    public static let meetings = Logger(subsystem: SuperFlowPaths.bundleID, category: "meetings")
    public static let updates = Logger(subsystem: SuperFlowPaths.bundleID, category: "updates")
}

// MARK: - Alerts

@MainActor
public enum Alerts {
    public static func error(_ message: String, _ error: Error? = nil) {
        Log.app.error("\(message, privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = message
        if let error { a.informativeText = error.localizedDescription }
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Confirmation with optional "Don't ask again" suppression (remembered in `suppressedWarnings`).
    public static func confirm(_ message: String, info: String = "", confirmTitle: String = "OK",
                               cancelTitle: String = "Cancel", destructive: Bool = false, suppressionID: String? = nil) -> Bool {
        if let id = suppressionID, Defaults[.suppressedWarnings].contains(id) { return true }
        let a = NSAlert()
        a.messageText = message
        a.informativeText = info
        let ok = a.addButton(withTitle: confirmTitle)
        if destructive { ok.hasDestructiveAction = true }
        a.addButton(withTitle: cancelTitle)
        if suppressionID != nil { a.showsSuppressionButton = true; a.suppressionButton?.title = "Don't ask again." }
        NSApp.activate(ignoringOtherApps: true)
        let result = a.runModal() == .alertFirstButtonReturn
        if result, let id = suppressionID, a.suppressionButton?.state == .on { Defaults[.suppressedWarnings].insert(id) }
        return result
    }
}

// MARK: - Screens & permissions

public extension NSScreen {
    /// The screen containing the mouse cursor (the Flow Bar follows it, ui-reference.md §2.2).
    static var active: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
    static func with(displayID: CGDirectDisplayID) -> NSScreen? { screens.first { $0.displayID == displayID } }
}

/// Privacy permissions Super Flow checks (behaviour.md §15).
public enum Permissions {
    /// Privacy & Security panes in System Settings.
    public enum Pane: String, Sendable {
        case accessibility = "Privacy_Accessibility"
        case microphone = "Privacy_Microphone"
        case screenRecording = "Privacy_ScreenCapture"
        case calendars = "Privacy_Calendars"
        case inputMonitoring = "Privacy_ListenEvent"
        case audioCapture = "Privacy_AudioCapture"
    }

    /// Whether Super Flow may read the focused text field and post keyboard events.
    public static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt when not yet trusted; returns the current trust.
    @discardableResult public static func requestAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    @MainActor public static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The Mac this runs on, for presets (local-models.md §9.2).
public enum Machine {
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
    public static var memoryBytes: Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }
    public static var isMacOS26OrLater: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 }
}

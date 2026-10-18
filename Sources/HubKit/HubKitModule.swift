import AppKit
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum HubKitModule {
    @MainActor public static func install() {
        Services.hub = Hub.shared
        Services.onboarding = Onboarding.shared
    }
}

/// Placeholder hub window (behaviour.md §12, ui-reference.md §3): a plain window with the app name so the Dock app
/// has something to show when reopened. Pages, settings and the Notepad are the module's next step.
@MainActor
final class Hub: HubPresenting {
    static let shared = Hub()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(_ page: HubPage) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: SFMetrics.Hub.defaultSize),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Super Flow"
            w.minSize = SFMetrics.Hub.minimumSize
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = SFColor.backgroundTertiary
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(_ pane: SettingsPane) { show(.settings) }
    func showMeeting(_ id: UUID) { show(.notetaker) }
    func showNotepad(for meetingID: UUID) { show(.notetaker) }
}

/// Placeholder onboarding (behaviour.md §14): reports the stored completion flag and shows the hub.
@MainActor
final class Onboarding: OnboardingPresenting {
    static let shared = Onboarding()
    var isCompleted: Bool { Defaults[.isOnboardingCompleted] }
    func show() { Services.hub.show(.home) }
    func restartTutorial() { Services.hub.show(.home) }
}

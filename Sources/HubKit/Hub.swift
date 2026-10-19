import AppKit
import Combine
import SwiftUI
import SuperFlowCore

/// The hub window (behaviour.md §12, ui-reference.md §3): sidebar pages, the Settings modal, the meeting pages and,
/// until it is completed, onboarding. One window; the Dock icon reopens it.
@MainActor
final class Hub: HubPresenting {
    static let shared = Hub()

    let state = HubState()
    private(set) lazy var store = HubStore()
    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    var isVisible: Bool { window?.isVisible ?? false }

    func show(_ page: HubPage) {
        if !Defaults[.isOnboardingCompleted] { Onboarding.shared.show(); return }
        state.mode = .hub
        state.open(page)
        present()
    }

    func showSettings(_ pane: SettingsPane) {
        if !Defaults[.isOnboardingCompleted] { Onboarding.shared.show(); return }
        state.mode = .hub
        state.settingsPane = pane
        present()
    }

    func showMeeting(_ id: UUID) {
        state.mode = .hub
        state.settingsPane = nil
        state.openMeeting(id)
        present()
    }

    /// The meeting being recorded, opened on its notes (the docked Notepad window is a later step; see the report).
    func showNotepad(for meetingID: UUID) {
        state.mode = .hub
        state.settingsPane = nil
        state.openMeeting(meetingID, tab: .notes)
        present()
    }

    /// The bar's Quick note: Notes, with a blank note in front and its editor taking the keyboard, so holding the
    /// shortcut dictates straight into it.
    func showQuickNote() {
        if !Defaults[.isOnboardingCompleted] { Onboarding.shared.show(); return }
        state.mode = .hub
        state.settingsPane = nil
        state.modal = nil
        state.go(.notes)
        state.quickNoteID = store.notes.quickNote().id
        present()
    }

    /// Shows onboarding in the hub window (forced light, §1.2).
    func presentOnboarding(from step: OnboardingStep, steps: [OnboardingStep]) {
        state.settingsPane = nil
        state.modal = nil
        state.onboardingSteps = steps
        state.onboardingStep = step
        state.mode = .onboarding
        present()
    }

    private func present() {
        let window = self.window ?? makeWindow()
        applyAppearance()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let w = HubWindow.make(rootView: HubRootView(state: state, store: store))
        w.setFrameAutosaveName("SuperFlowHub")
        window = w
        Defaults.publisher(.theme).dropFirst().sink { [weak self] _ in self?.applyAppearance() }.store(in: &cancellables)
        state.$mode.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.applyAppearance() } }
            .store(in: &cancellables)
        return w
    }

    private func applyAppearance() {
        window?.appearance = HubWindow.appearance(onboarding: state.mode == .onboarding)
    }
}

/// Window construction shared by the live hub and the offscreen renders.
@MainActor
enum HubWindow {
    static func make<Content: View>(rootView: Content, size: NSSize? = nil) -> NSWindow {
        let visible = NSScreen.main?.visibleFrame.size ?? SFMetrics.Hub.defaultSize
        let target = size ?? NSSize(width: min(SFMetrics.Hub.defaultSize.width, visible.width - 20),
                                    height: min(SFMetrics.Hub.defaultSize.height, visible.height - 20))
        let w = HubNSWindow(contentRect: NSRect(origin: .zero, size: target),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Super Flow"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.minSize = SFMetrics.Hub.minimumSize
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.backgroundColor = SFColor.backgroundTertiary
        let host = NSHostingView(rootView: rootView)
        // The window keeps its own size limits; SwiftUI's minimum heights (wrapping text measured at zero width)
        // would otherwise grow it.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: target)
        w.contentView = host
        w.center()
        w.placeTrafficLights()
        return w
    }

    /// Onboarding always draws light; the hub follows Settings › System › Appearance.
    static func appearance(onboarding: Bool) -> NSAppearance? {
        if onboarding { return NSAppearance(named: .aqua) }
        switch Defaults[.theme] {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

/// The hub window with its traffic lights lowered into the 60 pt header (ui-reference.md §3.1: at 16, 19), the way
/// Electron's `trafficLightPosition` does it: a taller titlebar container and the buttons moved inside it.
final class HubNSWindow: NSWindow {
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        placeTrafficLights()
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        placeTrafficLights()
    }

    func placeTrafficLights() {
        guard !styleMask.contains(.fullScreen),
              let close = standardWindowButton(.closeButton), let mini = standardWindowButton(.miniaturizeButton),
              let zoom = standardWindowButton(.zoomButton), let container = close.superview?.superview,
              let frameView = container.superview else { return }
        let origin = SFMetrics.Hub.trafficLights
        let height = close.frame.height + origin.y * 2
        let frame = NSRect(x: 0, y: frameView.bounds.height - height, width: frameView.bounds.width, height: height)
        if container.frame != frame { container.frame = frame }
        let step = max(mini.frame.minX - close.frame.minX, 20)
        for (i, button) in [close, mini, zoom].enumerated() {
            let target = NSPoint(x: origin.x + CGFloat(i) * step, y: height - origin.y - button.frame.height)
            if button.frame.origin != target { button.setFrameOrigin(target) }
        }
    }
}

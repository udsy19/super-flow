import AppKit
import SuperFlowCore

/// The bar's window (ui-reference.md §2.1): a borderless, transparent, non-activating panel at screen-saver level on
/// every Space and over full-screen apps. It never becomes key or main, so clicking the bar leaves the focus (and the
/// caret dictation types into) where it was. Mouse events pass through except over the bar's hot area.
final class FlowBarPanel: NSPanel {
    init() {
        super.init(contentRect: CGRect(origin: .zero, size: SFMetrics.FlowBar.bottomWindowSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        title = "Flow Bar"
        isFloatingPanel = true
        level = SFMetrics.FlowBar.windowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// An `NSMenuItem` that runs a closure (the bar's menus are built on demand).
final class FlowBarMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, enabled: Bool = true, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

/// Drives the canvas from the screen's refresh (`NSView.displayLink`, macOS 14) and pauses when nothing moves.
@MainActor
final class FlowBarFrameDriver: NSObject {
    private var link: CADisplayLink?
    private let onFrame: () -> Bool

    init(view: NSView, onFrame: @escaping () -> Bool) {
        self.onFrame = onFrame
        super.init()
        link = view.displayLink(target: self, selector: #selector(frame))
        link?.add(to: .main, forMode: .common)
        link?.isPaused = true
    }

    func run() { link?.isPaused = false }

    func invalidate() { link?.invalidate(); link = nil }

    @objc private func frame() {
        if !onFrame() { link?.isPaused = true }
    }
}

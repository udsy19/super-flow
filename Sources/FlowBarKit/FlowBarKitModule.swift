import AppKit
import Combine
import SuperFlowCore

/// Registers this module's service in `Services` (called once at launch).
public enum FlowBarKitModule {
    @MainActor public static func install() {
        Services.flowBar = FlowBar.shared
        FlowBar.shared.connect()
    }
}

/// The Flow Bar (behaviour.md §5, §18, §20.1; ui-reference.md §2, §10.2): the floating pill at the bottom centre of
/// the active screen, its states, the cards above it and the meeting-detected prompt. `FlowBarModel` holds the state
/// machine; this class feeds it, owns the panel, and turns clicks into service calls.
@MainActor
public final class FlowBar: FlowBarPresenting {
    public static let shared = FlowBar(showsPanel: true)

    public private(set) var model = FlowBarModel()
    public var state: FlowBarState { model.state }
    /// The clock; the self-test pins it.
    public var now: () -> Date = Date.init

    private let showsPanel: Bool
    private var panel: FlowBarPanel?
    private var canvas: FlowBarCanvas?
    private var driver: FlowBarFrameDriver?
    private var ticker: Timer?
    private var tickInterval: TimeInterval = 0
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var notificationActions: [String: (String) -> Void] = [:]
    private var promptAnswer: ((MeetingPromptAnswer) -> Void)?
    private var pressed: FlowBarElement?
    private var holdTimer: Timer?
    private var holdingToTalk = false
    private var snoozeTimer: Timer?
    /// Where `reposition` last sent the window (the panel's own frame is in between while it glides there).
    private var placedFrame: CGRect?

    /// Pressing the ready pill this long starts push-to-talk until release; a shorter click starts hands-free.
    static let holdToTalkDelay: TimeInterval = 0.35

    /// `showsPanel: false` keeps everything off screen (the self-test drives the state machine only).
    public init(showsPanel: Bool) {
        self.showsPanel = showsPanel
        readDefaults()
    }

    /// Follows the settings and the microphone level.
    func connect() {
        let keys: Set<String> = [Defaults.Keys.enableSounds.name, Defaults.Keys.flowBarHiddenUntil.name, Defaults.Keys.shortcuts.name,
                                 Defaults.Keys.hideMeetingRecorderInScreenShare.name]
        Defaults.changes
            .filter { keys.contains($0) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.readDefaults(); self?.refresh() } }
            .store(in: &subscriptions)
        if let audio = Services.audio {
            audio.level.receive(on: DispatchQueue.main)
                .sink { [weak self] level in MainActor.assumeIsolated { self?.setLevel(level) } }
                .store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.canvas?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } }
            .store(in: &subscriptions)
        // Where the bar sits changes with the space (full screen or not), the app in front, the displays and the
        // Dock's settings; the 400 ms tick catches the rest (an auto-hidden Dock, a window entering full screen).
        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.MergeMany(
            workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            workspace.publisher(for: NSWorkspace.didActivateApplicationNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification),
            DistributedNotificationCenter.default().publisher(for: FlowBar.dockPreferencesChanged)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
        .store(in: &subscriptions)
    }

    /// Posted when the Dock's settings change (size, position, hiding).
    static let dockPreferencesChanged = Notification.Name("com.apple.dock.prefchanged")

    private func readDefaults() {
        model.soundsOn = Defaults[.enableSounds]
        model.hiddenUntil = Date(timeIntervalSince1970: Defaults[.flowBarHiddenUntil])
        model.pushToTalkShortcut = Defaults[.shortcuts].chords(for: .pushToTalk).first?.displayString ?? "Fn"
    }

    // MARK: FlowBarPresenting

    public func setState(_ state: FlowBarState) {
        model.setState(state, now: now())
        refresh()
    }

    public func setMeetingPhase(_ phase: MeetingBarPhase?) {
        model.setMeetingPhase(phase, now: now())
        refresh()
    }

    public func setLevel(_ level: Float) {
        guard let canvas else { return }
        canvas.level.target = canvas.scene.showsLevel ? Double(min(max(level, 0), 1)) : 0
        driver?.run()
    }

    public func setEdge(_ edge: FlowBarEdge) {
        guard edge != model.edge else { return }
        model.edge = edge
        reposition(force: true)
        refresh(animated: false)
    }

    public func setRestingVisible(_ visible: Bool) {
        model.restingVisible = visible
        refresh()
    }

    public func show(_ notification: FlowBarNotification, onAction: @escaping (String) -> Void) {
        if let old = model.notification, old.id != notification.id { notificationActions[old.id] = nil }
        model.show(notification, now: now())
        notificationActions[notification.id] = onAction
        if Defaults[.enableSounds] {
            switch notification.variant {
            case .error: Services.audio?.play(.notificationError)
            case .alert: Services.audio?.play(.notificationAlert)
            case .success: Services.audio?.play(.notificationSuccess)
            case .mini, .condensed, .standard: break
            }
        }
        refresh()
    }

    public func dismiss(notificationID: String) {
        guard model.dismissNotification(id: notificationID) else { return }
        notificationActions[notificationID] = nil
        refresh()
    }

    public func showMeetingPrompt(_ prompt: MeetingPrompt, onAnswer: @escaping (MeetingPromptAnswer) -> Void) {
        let previous = promptAnswer
        promptAnswer = onAnswer
        model.showPrompt(prompt, now: now())
        refresh()
        previous?(.dismissed)
    }

    public func showLiveText(_ text: String?) {
        model.liveText = text
        refresh()
    }

    // MARK: Answers (also driven by the self-test)

    /// The prompt's choice; nil when it timed out.
    public func answerPrompt(_ choice: FlowBarPromptChoice?) {
        guard model.prompt != nil else { return }
        let handler = promptAnswer
        promptAnswer = nil
        model.clearPrompt()
        refresh()
        switch choice {
        case .record?: handler?(.record)
        case .notNow?: handler?(.notThisOne)
        case .neverForApp?: handler?(.neverForThisApp)
        case nil: handler?(.dismissed)
        }
    }

    /// Runs a card action: the handler gets the action's title, then the card closes.
    public func performNotificationAction(id: String, index: Int) {
        guard let n = model.notification, n.id == id, n.actions.indices.contains(index) else { return }
        let handler = notificationActions[id]
        dismiss(notificationID: id)
        handler?(n.actions[index])
    }

    /// Closes cards whose time ran out and the prompt when it expires; true when something changed.
    @discardableResult public func expireTimedOut() -> Bool {
        let t = now()
        var changed = false
        if let id = model.expiredNotification(at: t) { dismiss(notificationID: id); changed = true }
        if model.promptExpired(at: t) { answerPrompt(nil); changed = true }
        return changed
    }

    /// The pointer over the bar (window coordinates), as the mouse monitors report it.
    public func pointer(inside: Bool, over element: FlowBarElement?) {
        guard inside != model.pointerInside || element != model.hovered else { return }
        model.pointerInside = inside
        model.hovered = element
        refresh()
    }

    // MARK: Drawing and windows

    private func refresh(animated: Bool = true) {
        let scene = model.scene(at: now())
        guard showsPanel else { return }
        scheduleSnoozeEnd()
        if panel == nil {
            guard scene.hasVisibleContent else { return }
            buildPanel()
        }
        guard let panel, let canvas else { return }
        if canvas.scene != scene { canvas.apply(scene, animated: animated) }
        if !scene.showsLevel { canvas.level.target = 0 }
        panel.sharingType = model.meetingPhase != nil && Defaults[.hideMeetingRecorderInScreenShare] ? .none : .readOnly
        if scene.hasVisibleContent && !panel.isVisible {
            reposition(force: true)
            panel.level = SFMetrics.FlowBar.windowLevel
            panel.orderFrontRegardless()
            installMonitors()
        }
        driver?.run()
        scheduleTicker(scene)
        trackPointer()
    }

    private func buildPanel() {
        let panel = FlowBarPanel()
        let canvas = FlowBarCanvas(frame: CGRect(origin: .zero, size: panel.frame.size))
        canvas.autoresizingMask = [.width, .height]
        canvas.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.group)
        canvas.setAccessibilityLabel("Flow Bar")
        canvas.onMouseDown = { [weak self] element, _ in self?.mouseDown(element) }
        canvas.onMouseUp = { [weak self] element, _ in self?.mouseUp(element) }
        canvas.onRightMouseDown = { [weak self] event in self?.showMenu(event) }
        canvas.onActivate = { [weak self] element in self?.activate(element) }
        panel.contentView = canvas
        self.panel = panel
        self.canvas = canvas
        driver = FlowBarFrameDriver(view: canvas) { [weak self] in self?.frame() ?? false }
        reposition(force: true)
    }

    /// "Hide for 1 hour" ends on its own: the window may be gone by then, so a timer brings the bar back.
    private func scheduleSnoozeEnd() {
        let until = model.hiddenUntil
        guard until > now() else { snoozeTimer?.invalidate(); snoozeTimer = nil; return }
        guard snoozeTimer?.fireDate != until else { return }
        snoozeTimer?.invalidate()
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }

    /// One display frame: animate, and put the window away once nothing is left to show.
    private func frame() -> Bool {
        guard let canvas, let panel else { return false }
        let more = canvas.step()
        if !more && !canvas.scene.hasVisibleContent && panel.isVisible {
            panel.orderOut(nil)
            stopFollowingPointer()
        }
        return more
    }

    /// Follows the display under the cursor and, on it, the Dock: above it while it shows, at the bottom edge in a
    /// full-screen space or with the Dock hidden (§2.2, `FlowBarPlacement`). A short move on the same display glides
    /// at AppKit's own window-move pace; another display or edge, a hidden window or Reduce Motion jump.
    private func reposition(force: Bool = false) {
        guard let panel else { return }
        let frame = FlowBarPlacement.windowFrame(edge: model.edge, on: .current(NSScreen.active))
        guard force || frame != placedFrame else { return }
        let from = placedFrame ?? panel.frame
        placedFrame = frame
        let sizeChanged = frame.size != panel.frame.size
        if !force, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           FlowBarPlacement.animatesMove(from: from, to: frame) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = panel.animationResizeTime(frame)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: false)
            }
        } else {
            panel.setFrame(frame, display: false)
        }
        if sizeChanged, let canvas { canvas.apply(model.scene(at: now()), animated: false) }
    }

    /// Re-reads the screen every 400 ms, and every 200 ms while a clock or countdown shows.
    private func scheduleTicker(_ scene: FlowBarScene) {
        let interval = scene.hasClock ? 0.2 : SFMetrics.FlowBar.followCursorInterval
        guard panel?.isVisible == true else { ticker?.invalidate(); ticker = nil; tickInterval = 0; return }
        guard interval != tickInterval else { return }
        ticker?.invalidate()
        tickInterval = interval
        ticker = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        reposition()
        if !expireTimedOut() { refresh() }
    }

    // MARK: Pointer

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.trackPointer() }
            return event
        }) { monitors.append(local) }
    }

    private func stopFollowingPointer() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        ticker?.invalidate(); ticker = nil; tickInterval = 0
    }

    /// Mouse events reach the panel only over the hot area; elsewhere they go to the app below.
    private func trackPointer() {
        guard let panel, let canvas, panel.isVisible else { return }
        let p = NSEvent.mouseLocation
        let local = CGPoint(x: p.x - panel.frame.minX, y: p.y - panel.frame.minY)
        let inside = canvas.frames.hotRects.contains { $0.contains(local) }
        panel.ignoresMouseEvents = !inside
        pointer(inside: inside, over: inside ? canvas.element(at: local) : nil)
    }

    // MARK: Clicks

    private func mouseDown(_ element: FlowBarElement?) {
        pressed = element
        holdTimer?.invalidate()
        guard element == .pill, case .ready = model.scene(at: now()).pill else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: FlowBar.holdToTalkDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pressed == .pill else { return }
                self.holdingToTalk = true
                Services.dictation?.start(mode: .pushToTalk, source: .statusIndicator)
            }
        }
    }

    private func mouseUp(_ element: FlowBarElement?) {
        holdTimer?.invalidate(); holdTimer = nil
        defer { pressed = nil }
        if holdingToTalk {
            holdingToTalk = false
            Services.dictation?.finish()
            return
        }
        guard let element, element == pressed else { return }
        activate(element)
    }

    /// What each element does when clicked.
    private func activate(_ element: FlowBarElement) {
        let scene = model.scene(at: now())
        switch element {
        case .pill:
            if case .ready = scene.pill { Services.dictation?.start(mode: .handsFree, source: .statusIndicator) }
        case .cancel: Services.dictation?.dismiss(.userCancelButton)
        case .finish: Services.dictation?.finish()
        case .meetingStop: Task { await Services.meetingRecorder?.stop() }
        case .meetingBody:
            if case .recording(let id)? = Services.meetingRecorder?.state { Services.hub?.showNotepad(for: id) }
        case .picker(.hub): Services.hub?.show(.home)
        case .picker(.quickNote): Services.hub?.showQuickNote()
        case .picker(.sounds): Defaults[.enableSounds].toggle()
        case .cardAction(let id, let index): performNotificationAction(id: id, index: index)
        case .cardClose(let id): dismiss(notificationID: id)
        case .prompt(let choice): answerPrompt(choice)
        }
    }

    // MARK: Menus (§5.5, §6.1: a native menu)

    private func showMenu(_ event: NSEvent) {
        guard let canvas, canvas.scene.pill != .hidden else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(FlowBarMenuItem(FlowBarCopy.pasteLast) { Services.dictation?.pasteLastTranscript() })
        menu.addItem(FlowBarMenuItem(FlowBarCopy.history) { Services.hub?.show(.home) })
        menu.addItem(.separator())
        if let audio = Services.audio, !audio.devices.isEmpty {
            let mics = NSMenuItem(title: FlowBarCopy.microphone, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for device in audio.devices {
                let item = FlowBarMenuItem(device.name, checked: device.id == audio.selectedDevice?.id, enabled: device.unavailableReason == nil) {
                    Defaults[.overrideAudioDeviceId] = device.id
                }
                item.toolTip = device.unavailableReason
                sub.addItem(item)
            }
            mics.submenu = sub
            menu.addItem(mics)
        }
        let languages = NSMenuItem(title: FlowBarCopy.languages, action: nil, keyEquivalent: "")
        languages.submenu = languageMenu()
        menu.addItem(languages)
        menu.addItem(.separator())
        menu.addItem(FlowBarMenuItem(FlowBarCopy.hideForHour) { [weak self] in self?.hideForAnHour() })
        menu.addItem(FlowBarMenuItem(FlowBarCopy.settings) { Services.hub?.showSettings(.general) })
        NSMenu.popUpContextMenu(menu, with: event, for: canvas)
    }

    private func languageMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let auto = Defaults[.autoDetectLanguage]
        menu.addItem(FlowBarMenuItem(FlowBarCopy.detectAutomatically, checked: auto) { Defaults[.autoDetectLanguage] = true })
        let selected = Defaults[.selectedLanguages]
        if !selected.isEmpty { menu.addItem(.separator()) }
        for (index, code) in selected.enumerated() {
            let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
            menu.addItem(FlowBarMenuItem(name, checked: !auto && index == 0) {
                Defaults[.selectedLanguages] = [code] + selected.filter { $0 != code }
                Defaults[.autoDetectLanguage] = false
            })
        }
        menu.addItem(.separator())
        menu.addItem(FlowBarMenuItem(FlowBarCopy.manageLanguages) { Services.hub?.showSettings(.general) })
        return menu
    }

    /// "Hide for 1 hour" with an Undo card (§5.1, §2.15).
    private func hideForAnHour() {
        Defaults[.flowBarHiddenUntil] = now().addingTimeInterval(3600).timeIntervalSince1970
        show(FlowBarNotification(id: "flowBar.hidden", title: FlowBarCopy.hiddenForHour, actions: [FlowBarCopy.undo])) { _ in
            Defaults[.flowBarHiddenUntil] = 0
        }
    }
}

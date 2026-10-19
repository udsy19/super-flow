import AppKit
import ApplicationServices
import SuperFlowCore

enum HotkeyError: LocalizedError {
    case accessibilityRequired

    var errorDescription: String? { "Super Flow needs accessibility access to work properly." }
}

/// HotkeyMonitoring (behaviour.md §3): the event tap, its permission state, secure input and the Fn keyboard check.
///
/// `start()` throws when neither Accessibility nor Input Monitoring is granted, and keeps checking every second
/// until `stop()`: the tap comes up by itself once permission is granted (onboarding), turns from listen-only into
/// active when Accessibility arrives, and goes away (releasing held chords) when it is revoked. Nothing here
/// prompts for a permission.
@MainActor
final class HotkeyMonitor: HotkeyMonitoring {
    static let shared = HotkeyMonitor()

    let events: AsyncStream<HotkeyEvent>
    let recorderEvents: AsyncStream<KeyChord>
    private let eventContinuation: AsyncStream<HotkeyEvent>.Continuation
    private let tap: EventTap
    private var mode: HotkeyTapMode?
    /// The permission state the tap was last set up for.
    private var grantedMode: HotkeyTapMode?
    private var wanted = false
    private var healthTimer: Timer?
    private var secureInputBlocked = false
    private var sawFnKey = false

    var isRunning: Bool { mode != nil }
    var tapMode: HotkeyTapMode? { mode }
    var isRecording = false { didSet { tap.setRecording(isRecording) } }
    /// An Fn press seen by the tap settles it; otherwise the connected keyboards decide.
    var hasFnKey: Bool { sawFnKey || FnKeyboard.hasFnKey(FnKeyboard.connected()) }

    private init() {
        let (events, eventContinuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        let (recorderEvents, recorderContinuation) = AsyncStream.makeStream(of: KeyChord.self)
        self.events = events
        self.recorderEvents = recorderEvents
        self.eventContinuation = eventContinuation
        tap = EventTap(map: Defaults[.shortcuts], output: { decision in
            decision.events.forEach { eventContinuation.yield($0) }
            if let chord = decision.recorded { recorderContinuation.yield(chord) }
        }, fnSeen: {
            Task { @MainActor in HotkeyMonitor.shared.sawFnKey = true }
        })
    }

    func start() throws {
        wanted = true
        if healthTimer == nil {
            healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkHealth() }
            }
        }
        connectTap()
        if mode == nil { throw HotkeyError.accessibilityRequired }
    }

    func stop() {
        wanted = false
        healthTimer?.invalidate()
        healthTimer = nil
        tap.uninstall()
        mode = nil
        grantedMode = nil
    }

    func update(_ map: ShortcutMap) { tap.setMap(map) }

    /// Matches the tap to the permissions granted right now. It is rebuilt only when they change (rebuilding releases
    /// held keys), or retried while a permitted tap failed to come up.
    private func connectTap() {
        let trusted = AXIsProcessTrusted()
        let canListen = trusted || CGPreflightListenEventAccess()
        let granted: HotkeyTapMode? = trusted ? .active : canListen ? .listenOnly : nil
        guard granted != grantedMode || (granted != nil && mode == nil) else { return }
        grantedMode = granted
        let previous = mode
        if granted == nil {
            tap.uninstall()
            mode = nil
        } else {
            mode = tap.install(trusted: trusted, canListen: canListen)
        }
        if mode != previous { Log.hotkeys.info("Event tap: \(self.mode?.rawValue ?? "off", privacy: .public)") }
    }

    private func checkHealth() {
        guard wanted else { return }
        connectTap()
        let blocked = SecureInput.isEnabled
        guard blocked != secureInputBlocked else { return }
        secureInputBlocked = blocked
        let owner = blocked ? SecureInput.ownerBundleID() : nil
        Log.hotkeys.info("Secure input \(blocked ? "on" : "off", privacy: .public) \(owner ?? "", privacy: .public)")
        eventContinuation.yield(.secureInput(blocked: blocked, ownerBundleID: owner))
        // Keys released while the tap was blind never reported their key-up.
        tap.revalidate()
    }
}

/// The CGEventTap and the chord engine, on a thread of their own: an active tap holds every key the user types until
/// its callback returns, so it must never wait behind the main thread (AX reads, UI). The engine is only touched on
/// that thread; the main actor reaches it through `sync`/`async` blocks, and decisions leave through `output`.
final class EventTap: @unchecked Sendable {
    private let runLoop: CFRunLoop
    private var engine: ChordEngine
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var sweepTimer: CFRunLoopTimer?
    private var canSwallow = false
    private var reportedFn = false
    private let output: @Sendable (ChordDecision) -> Void
    private let fnSeen: @Sendable () -> Void

    init(map: ShortcutMap, output: @escaping @Sendable (ChordDecision) -> Void, fnSeen: @escaping @Sendable () -> Void) {
        engine = ChordEngine(map: map)
        self.output = output
        self.fnSeen = fnSeen
        runLoop = Self.startThread()
    }

    /// Creates the tap: active when `trusted`, else listen-only when `canListen`. Returns what was installed.
    func install(trusted: Bool, canListen: Bool) -> HotkeyTapMode? {
        sync { [self] in
            removeTap()
            let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseUp]
            let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            let candidates: [(CGEventTapOptions, HotkeyTapMode)] = (trusted ? [(.defaultTap, .active)] : []) + (canListen ? [(.listenOnly, .listenOnly)] : [])
            for (options, mode) in candidates {
                guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
                                                   eventsOfInterest: mask, callback: eventTapCallback,
                                                   userInfo: Unmanaged.passUnretained(self).toOpaque()) else { continue }
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
                CFRunLoopAddSource(runLoop, source, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
                let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + DictationLimits.staleKeySweepInterval,
                                                            DictationLimits.staleKeySweepInterval, 0, 0) { [weak self] _ in self?.periodicCheck() }
                CFRunLoopAddTimer(runLoop, timer, .commonModes)
                self.port = port
                self.source = source
                sweepTimer = timer
                canSwallow = mode == .active
                return mode
            }
            return nil
        }
    }

    func uninstall() { sync { [self] in removeTap() } }

    func setMap(_ map: ShortcutMap) { async { [self] in engine.map = map } }
    func setRecording(_ isRecording: Bool) { async { [self] in engine.isRecording = isRecording } }
    /// Re-checks every held key against the OS and releases those that are up.
    func revalidate() { async { [self] in apply(engine.sweep(at: Self.now, all: true, isPhysicallyDown: Self.isPhysicallyDown)) } }

    // MARK: - Tap thread

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.hotkeys.info("Event tap disabled by the system; re-enabling")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            apply(engine.sweep(at: Self.now, all: true, isPhysicallyDown: Self.isPhysicallyDown))
            return pass
        }
        // Our own ⌘V, ⌘C and Return must neither trigger nor be dropped.
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticKeys.marker { return pass }
        let now = Self.now
        if type == .flagsChanged {
            for code in KeyEventDecoder.releasedModifiers(held: engine.held.keys, flags: event.flags) {
                apply(engine.handle(code, isDown: false, at: now))
            }
        }
        guard let key = KeyEventDecoder.transition(type: type, keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                                   flags: event.flags, mouseButton: event.getIntegerValueField(.mouseEventButtonNumber))
        else { return pass }
        if key.code == KeyChord.fn, !reportedFn {
            reportedFn = true
            fnSeen()
        }
        let decision = engine.handle(key.code, isDown: key.isDown, at: now, isPhysicallyDown: Self.isPhysicallyDown)
        apply(decision)
        return decision.swallow && canSwallow ? nil : pass
    }

    /// Every sweep interval: re-enable a tap the system turned off without telling us, and drop stale keys (§3.3.8).
    private func periodicCheck() {
        guard let port else { return }
        if CGEvent.tapIsEnabled(tap: port) {
            apply(engine.sweep(at: Self.now, isPhysicallyDown: Self.isPhysicallyDown))
        } else {
            CGEvent.tapEnable(tap: port, enable: true)
            apply(engine.sweep(at: Self.now, all: true, isPhysicallyDown: Self.isPhysicallyDown))
        }
    }

    /// Removes the tap and releases every held key, so a chord held at that moment still reports its release.
    private func removeTap() {
        if let sweepTimer { CFRunLoopTimerInvalidate(sweepTimer) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFMachPortInvalidate(port)
        }
        port = nil
        source = nil
        sweepTimer = nil
        apply(engine.sweep(at: Self.now, all: true, isPhysicallyDown: { _ in false }))
    }

    private func apply(_ decision: ChordDecision) {
        if !decision.events.isEmpty || decision.recorded != nil { output(decision) }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// What the HID system says about a key right now. Mouse buttons past the middle one can't be queried and count
    /// as down (their own release event clears them).
    private static func isPhysicallyDown(_ code: UInt16) -> Bool {
        if code == KeyChord.fn { return CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn) }
        if code == KeyChord.mouseMiddle { return CGEventSource.buttonState(.hidSystemState, button: .center) }
        if KeyChord.isMouse(code) { return true }
        return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code))
    }

    // MARK: - Thread

    private static func startThread() -> CFRunLoop {
        final class Box: @unchecked Sendable { var runLoop: CFRunLoop? }
        let box = Box()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            // A run loop without a source returns at once; the port keeps this one waiting for work.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = "Super Flow hotkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return box.runLoop!
    }

    private func sync<T>(_ work: @escaping () -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        var result: T?
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            result = work()
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
        return result!
    }

    private func async(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}

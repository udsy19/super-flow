import Foundation
import SuperFlowCore

/// What the engine decided for one input: events for the app, a chord for the open shortcut recorder, and whether the
/// event tap drops the key so the frontmost app never sees it.
public struct ChordDecision: Equatable, Sendable {
    public var events: [HotkeyEvent] = []
    /// The chord the shortcut recorder captured: every key that was down, reported once all of them are up.
    public var recorded: KeyChord?
    public var swallow = false

    public init() {}
}

/// The shortcut matcher of behaviour.md §3.3 as pure logic: key transitions (KeyChord codes, so Fn is 63 and mouse
/// buttons are 4098…) with timestamps in, `HotkeyEvent`s and swallow decisions out. The event tap feeds it; the
/// self-test drives it with scripted timings.
///
/// - A chord fires `.pressed` when the keys down equal it exactly, and `.released` when any of its keys comes up.
///   A newer exact match replaces the active chord without a release (holding Fn, then Space: push-to-talk is
///   followed by hands-free; the coordinator applies the other-shortcut rule). Paste-last reports its release only
///   once all of its keys are up, so the synthetic ⌘V never meets a held ⌃⌘ (§3.3.7).
/// - A larger chord of the same action continues the active one without a new press (§3.3.3).
/// - Taps of a push-to-talk chord: a tap is a press shorter than `tapWindow` with no other key, and the next press
///   continues the sequence when it starts within `tapWindow` of the previous release. The second press of Fn
///   reports `.doubleTap` (when `doubleTapFnForHandsFree`), the third press of any push-to-talk chord `.tripleTap`;
///   those presses report nothing on release. Settings gates (triple-tap off, a locked session) are the
///   coordinator's.
/// - A single-key `.dismiss` chord (Esc) also fires while other keys are held (§3.3.5). Any other key that completes
///   no chord while a chord is held reports `.otherKey` once (the other-key cancel of §2.3).
/// - Only the key that completes a chord is swallowed, only when it is not a modifier, the chord has a modifier or a
///   mouse button, and the action is not `.dismiss`; its repeats and its release are swallowed with it. Modifiers,
///   Esc and keys that complete no chord always reach the app. While the recorder is open, non-modifier keys go to
///   the recorder only.
public struct ChordEngine: Sendable {
    public var map: ShortcutMap { didSet { endTapSequence() } }
    public var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            active = nil
            recorderKeys = []
            endTapSequence()
        }
    }
    public let tapWindow: TimeInterval
    public let verifyAfter: TimeInterval
    public let dropAfter: TimeInterval

    /// Keys down now, with the time each went down.
    public private(set) var held: [UInt16: TimeInterval] = [:]

    private struct ActiveChord: Sendable {
        var action: ShortcutAction
        var chord: KeyChord
        var since: TimeInterval
        /// No other key went down while it was held: a tap candidate.
        var clean = true
        /// Consumed by a double or triple tap: its release reports nothing.
        var ownedByGesture = false
    }

    private var active: ActiveChord?
    /// A paste-last chord whose release waits for its last key to come up.
    private var pendingFullRelease: ActiveChord?
    private var swallowed: Set<UInt16> = []
    private var tapCount = 0
    private var lastTapRelease: TimeInterval?
    private var recorderKeys: Set<UInt16> = []

    public init(map: ShortcutMap, tapWindow: TimeInterval = DictationLimits.debounceWindow,
                verifyAfter: TimeInterval = DictationLimits.staleKeyVerifyAfter, dropAfter: TimeInterval = DictationLimits.staleKeyDropAfter) {
        self.map = map; self.tapWindow = tapWindow; self.verifyAfter = verifyAfter; self.dropAfter = dropAfter
    }

    /// One key going down or up. `isPhysicallyDown` answers whether the OS still sees a key down; it is asked about
    /// keys held longer than `verifyAfter` before a new chord fires (§3.3.8).
    public mutating func handle(_ code: UInt16, isDown: Bool, at time: TimeInterval,
                                isPhysicallyDown: (UInt16) -> Bool = { _ in true }) -> ChordDecision {
        var out = ChordDecision()
        if isDown { press(code, at: time, isPhysicallyDown: isPhysicallyDown, into: &out) } else { release(code, at: time, into: &out) }
        return out
    }

    /// Drops held keys the OS reports as up: those held longer than `dropAfter` on the periodic sweep, or all of them
    /// with `all` (after the tap was re-enabled and may have missed releases). Releases fire as for a real key-up.
    public mutating func sweep(at time: TimeInterval, all: Bool = false, isPhysicallyDown: (UInt16) -> Bool) -> ChordDecision {
        var out = ChordDecision()
        for (code, since) in held where (all || time - since > dropAfter) && !isPhysicallyDown(code) {
            release(code, at: time, into: &out)
        }
        out.swallow = false
        return out
    }

    // MARK: - Press

    private mutating func press(_ code: UInt16, at time: TimeInterval, isPhysicallyDown: (UInt16) -> Bool, into out: inout ChordDecision) {
        if held[code] != nil {
            // Ordinary keys auto-repeat; modifiers and mouse buttons never do, so a second down means the up was missed.
            guard KeyChord.modifierCodes.contains(code) || KeyChord.isMouse(code) else {
                out.swallow = swallowed.contains(code)
                return
            }
            release(code, at: time, into: &out)
        }
        if isRecording {
            held[code] = time
            recorderKeys.insert(code)
            if !KeyChord.modifierCodes.contains(code) { swallowed.insert(code); out.swallow = true }
            return
        }
        for (key, since) in held where time - since > verifyAfter && !isPhysicallyDown(key) {
            release(key, at: time, into: &out)
        }
        held[code] = time
        let chord = KeyChord(Set(held.keys))

        guard let action = map.bindings[chord] else {
            if let current = active, current.clean, held.count > 1, map.bindings[KeyChord(code)] != .dismiss {
                out.events.append(.otherKey(during: current.action, current.chord))
            }
            active?.clean = false
            endTapSequence()
            if held.count > 1, map.bindings[KeyChord(code)] == .dismiss {
                out.events.append(.pressed(.dismiss, KeyChord(code)))
            }
            return
        }
        if action != .dismiss, !KeyChord.modifierCodes.contains(code), chord.hasModifierOrMouse {
            swallowed.insert(code)
            out.swallow = true
        }
        if let current = active, current.action == action, current.chord.keys.isStrictSubset(of: chord.keys) {
            active?.chord = chord
            active?.clean = false
            return
        }
        var next = ActiveChord(action: action, chord: chord, since: time)
        if action == .pushToTalk {
            let continues = tapCount > 0 && lastTapRelease.map { time - $0 <= tapWindow } == true
            tapCount = continues ? tapCount + 1 : 1
            lastTapRelease = nil
            if tapCount >= 3 {
                out.events.append(.tripleTap)
                next.ownedByGesture = true
                tapCount = 0
            } else if tapCount == 2, map.doubleTapFnForHandsFree, chord == KeyChord(KeyChord.fn) {
                out.events.append(.doubleTap)
                next.ownedByGesture = true
            } else {
                out.events.append(.pressed(action, chord))
            }
        } else {
            endTapSequence()
            out.events.append(.pressed(action, chord))
        }
        active = next
    }

    // MARK: - Release

    private mutating func release(_ code: UInt16, at time: TimeInterval, into out: inout ChordDecision) {
        if swallowed.remove(code) != nil { out.swallow = true }
        guard held.removeValue(forKey: code) != nil else { return }
        if isRecording {
            if held.isEmpty, !recorderKeys.isEmpty {
                out.recorded = KeyChord(recorderKeys)
                recorderKeys = []
            }
            return
        }
        if let pending = pendingFullRelease, pending.chord.keys.isDisjoint(with: held.keys) {
            out.events.append(.released(pending.action, pending.chord))
            pendingFullRelease = nil
        }
        guard let current = active, current.chord.keys.contains(code) else { return }
        active = nil
        if current.action == .pushToTalk {
            if current.clean, time - current.since < tapWindow { lastTapRelease = time } else { endTapSequence() }
        }
        if current.ownedByGesture { return }
        if current.action == .pasteLastText, !current.chord.keys.isDisjoint(with: held.keys) {
            pendingFullRelease = current
            return
        }
        out.events.append(.released(current.action, current.chord))
    }

    private mutating func endTapSequence() {
        tapCount = 0
        lastTapRelease = nil
    }
}

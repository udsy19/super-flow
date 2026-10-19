import Foundation
import SuperFlowCore

/// What the coordinator should do about one hotkey event, given the dictation's state (behaviour.md §2.2, §3.3). Pure,
/// so the self-test can drive every sequence, including the Fn+Space ones the event tap produces:
///
/// - Fn then Space arrives as a push-to-talk press followed by a hands-free press with no release in between: the
///   running push-to-talk session turns into a hands-free one.
/// - Stopping with Fn+Space arrives as a push-to-talk press (which finishes the session) followed by a hands-free
///   press, which lands on a busy session and is ignored; the debounce window covers the fast path too.
/// - Fn then Control is a push-to-talk press followed by a Command Mode press: the session turns into Command Mode.
public enum HotkeyRouter {
    public enum Intent: Equatable {
        case start(DictationMode)
        case finish
        case dismiss(DismissReason)
        case switchMode(DictationMode)
        /// Esc with nothing to dismiss: close the Flow Bar's cards.
        case closeCards
        case commandModeOff
        case transform(ShortcutAction)
        case notetaker
        case pasteLast, copyLast
        case openScratchpad
        case secureInput(blocked: Bool, ownerBundleID: String?)
        case none
    }

    public struct State: Equatable {
        public var status: DictationStatus
        public var mode: DictationMode?
        /// When the running session started.
        public var startedAt: Date?
        /// When the last session finished: a hands-free press within the debounce window afterwards is the tail of the
        /// Fn+Space gesture that finished it, not a new session.
        public var lastFinishAt: Date?
        public var commandModeEnabled: Bool
        public var tripleTapEnabled: Bool
        public var transformsEnabled: Bool

        public init(status: DictationStatus = .idle, mode: DictationMode? = nil, startedAt: Date? = nil, lastFinishAt: Date? = nil,
                    commandModeEnabled: Bool = false, tripleTapEnabled: Bool = true, transformsEnabled: Bool = true) {
            self.status = status; self.mode = mode; self.startedAt = startedAt; self.lastFinishAt = lastFinishAt
            self.commandModeEnabled = commandModeEnabled; self.tripleTapEnabled = tripleTapEnabled; self.transformsEnabled = transformsEnabled
        }

        var recording: Bool { status.isRecording }
        func within(_ window: TimeInterval, of date: Date?, now: Date) -> Bool {
            guard let date else { return false }
            return now.timeIntervalSince(date) < window
        }
        /// A press that follows a finish inside the debounce window belongs to the gesture that finished.
        func debounced(now: Date) -> Bool { within(DictationLimits.debounceWindow, of: lastFinishAt, now: now) }
    }

    public static func route(_ event: HotkeyEvent, state: State, now: Date) -> Intent {
        switch event {
        case .pressed(let action, _):
            return pressed(action, state: state, now: now)
        case .released(let action, _):
            switch action {
            case .pushToTalk: return state.recording && state.mode == .pushToTalk ? .finish : .none
            case .commandMode: return state.recording && state.mode == .command ? .finish : .none
            case .pasteLastText: return .pasteLast
            default: return .none
            }
        case .otherKey(during: let action, _):
            guard action == .pushToTalk, state.recording, state.mode == .pushToTalk,
                  state.within(DictationLimits.otherShortcutCancelWindow, of: state.startedAt, now: now) else { return .none }
            return .dismiss(.otherShortcut)
        case .doubleTap:
            return handsFreePressed(state: state, now: now)
        case .tripleTap:
            guard state.tripleTapEnabled, !(state.recording && state.mode == .handsFree) else { return .none }
            return .notetaker
        case .secureInput(let blocked, let owner):
            return .secureInput(blocked: blocked, ownerBundleID: owner)
        }
    }

    private static func pressed(_ action: ShortcutAction, state: State, now: Date) -> Intent {
        switch action {
        case .pushToTalk:
            if state.recording { return state.mode == .handsFree ? .finish : .none }
            guard state.status.canStart else { return .none }
            return .start(.pushToTalk)
        case .handsFree:
            return handsFreePressed(state: state, now: now)
        case .commandMode:
            if state.recording {
                guard state.mode == .pushToTalk else { return .none }
                return state.commandModeEnabled ? .switchMode(.command) : .commandModeOff
            }
            guard state.status.canStart else { return .none }
            return state.commandModeEnabled ? .start(.command) : .commandModeOff
        case .dismiss:
            return state.status.canStart ? .closeCards : .dismiss(.userEscape)
        case .pasteLastText:
            return .none   // fires on release (§3.3.7)
        case .copyLastText:
            return .copyLast
        case .transform, .transformPrompt1, .transformPrompt2:
            return state.transformsEnabled ? .transform(action) : .none
        case .notetaker:
            return .notetaker
        case .openScratchpad:
            return .openScratchpad
        case .focusMode, .viewDiff, .pressEnter:
            return .none
        }
    }

    private static func handsFreePressed(state: State, now: Date) -> Intent {
        if state.recording {
            switch state.mode {
            case .handsFree: return .finish
            case .pushToTalk: return .switchMode(.handsFree)
            case .command, nil: return .none
            }
        }
        guard state.status.canStart, !state.debounced(now: now) else { return .none }
        return .start(.handsFree)
    }
}

import Foundation
import SuperFlowCore

/// The circles that appear beside the pill on hover (ui-reference.md §2.9).
public enum FlowBarPicker: String, CaseIterable, Sendable {
    case hub, language, notes, sounds

    /// Before the pill (bottom edge: left; side edges: above), outermost first.
    public static let leading: [FlowBarPicker] = [.hub, .language]
    /// After the pill (bottom edge: right; side edges: below), innermost first.
    public static let trailing: [FlowBarPicker] = [.notes, .sounds]
}

/// The meeting-detected prompt's three choices.
public enum FlowBarPromptChoice: Hashable, Sendable {
    case record, notNow, neverForApp
}

/// Everything on the bar the pointer can hover or click.
public enum FlowBarElement: Hashable, Sendable {
    case pill
    case cancel, finish
    case meetingBody, meetingStop
    case picker(FlowBarPicker)
    case cardAction(id: String, index: Int)
    case cardClose(id: String)
    case prompt(FlowBarPromptChoice)
}

/// What the bar shows at one moment: a value derived from `FlowBarModel`, drawn by the canvas and the renders.
public struct FlowBarScene: Equatable, Sendable {
    public enum Pill: Equatable, Sendable {
        case hidden
        case resting
        /// Hover over the resting bar (or `FlowBarState.ready`): mic glyph, pickers beside it.
        case ready
        case initializing
        case pushToTalk
        case handsFree(elapsed: TimeInterval)
        case processing
        case preparing(fraction: Double)
        case transformProcessing(label: String, startedAt: Date)
        case transformCompleted
        case cleanupCompleted
        case error
        case meeting(MeetingBarPhase, elapsed: TimeInterval)
    }

    public var pill: Pill = .hidden
    /// Command Mode overlay: amber border, bars and spinner (§2.4).
    public var commandMode = false
    public var edge: FlowBarEdge = .bottom
    public var hovered: FlowBarElement?
    /// The dictation language shown on the language picker; nil when detecting automatically.
    public var languageCode: String?
    public var soundsOn = true
    /// Shown in the dictate tooltip ("Click or hold Fn to dictate").
    public var pushToTalkShortcut = "Fn"
    public var notification: FlowBarNotification?
    public var notificationShownAt: Date?
    public var prompt: MeetingPrompt?
    public var promptShownAt: Date?
    public var liveText: String?

    public init() {}

    public var showsPickers: Bool { pill == .ready }

    /// Whether anything is on screen (the window can go away otherwise).
    public var hasVisibleContent: Bool { pill != .hidden || notification != nil || prompt != nil || liveText != nil }

    /// Whether the pill shows a clock or a countdown that changes every second.
    public var hasClock: Bool {
        switch pill {
        case .handsFree, .meeting: return true
        default: return prompt != nil || notification?.timeout != nil
        }
    }

    /// The pill reads the microphone level (dictation or meeting waveform).
    public var showsLevel: Bool {
        if case .meeting = pill { return true }
        return isListening
    }

    /// Whether the pill is one of the dictation states that hold the microphone.
    public var isListening: Bool {
        switch pill {
        case .initializing, .pushToTalk, .handsFree: true
        default: false
        }
    }

    /// The tooltip for the hovered element, nil when it has none.
    public var tooltip: [FlowBarCopy.Run]? {
        guard let hovered else { return nil }
        func plain(_ s: String) -> [FlowBarCopy.Run] { [FlowBarCopy.Run(s)] }
        switch hovered {
        case .pill:
            switch pill {
            case .ready: return FlowBarCopy.dictateTooltip(shortcut: pushToTalkShortcut)
            case .preparing: return plain(FlowBarCopy.preparingTooltip)
            default: return nil
            }
        case .cancel: return plain(FlowBarCopy.cancel)
        case .finish: return plain(FlowBarCopy.finish)
        case .meetingStop: return plain(FlowBarCopy.stopNotetaker)
        case .meetingBody:
            guard case .meeting(let phase, _) = pill else { return nil }
            switch phase {
            case .pending: return plain(FlowBarCopy.meetingStarting)
            case .recording(let words, _): return plain(FlowBarCopy.words(words))
            case .reconnecting: return plain(FlowBarCopy.meetingReconnecting)
            case .stopping: return plain(FlowBarCopy.meetingWrappingUp)
            }
        case .picker(.hub): return plain(FlowBarCopy.openHub)
        case .picker(.language): return plain(FlowBarCopy.language(code: languageCode))
        case .picker(.notes): return plain(FlowBarCopy.takeNotes)
        case .picker(.sounds): return plain(soundsOn ? FlowBarCopy.muteSounds : FlowBarCopy.unmuteSounds)
        case .cardAction, .cardClose, .prompt: return nil
        }
    }
}

/// The Flow Bar's state machine (behaviour.md §5, ui-reference.md §2.4, §2.15, §10.2). Pure: every input carries
/// its time, and `scene(at:)` derives what to draw. `FlowBar` feeds it from `FlowBarPresenting` and the pointer.
public struct FlowBarModel: Equatable, Sendable {
    /// What the last `setState` asked for, after meeting chrome is restored (see `setState`).
    public private(set) var state: FlowBarState = .hidden
    /// The Notetaker phase while a meeting records; kept underneath dictation states, which win (§10.2).
    public private(set) var meetingPhase: MeetingBarPhase?
    public private(set) var meetingStartedAt: Date?
    public private(set) var listeningStartedAt: Date?
    public private(set) var transformStartedAt: Date?
    /// Set by a Command Mode dictation and kept through its processing.
    public private(set) var commandMode = false

    public var edge: FlowBarEdge = .bottom
    /// The pointer is over the bar's hot area.
    public var pointerInside = false
    public var hovered: FlowBarElement?
    /// "Show Flow Bar at all times"; false hides the resting bar (active states still show, §2.15).
    public var restingVisible = true
    /// "Hide for 1 hour" snooze.
    public var hiddenUntil: Date = .distantPast
    public var languageCode: String?
    public var soundsOn = true
    public var pushToTalkShortcut = "Fn"

    public private(set) var notification: FlowBarNotification?
    public private(set) var notificationShownAt: Date?
    public private(set) var prompt: MeetingPrompt?
    public private(set) var promptShownAt: Date?
    public var liveText: String?

    public init() {}

    // MARK: State

    /// The Notetaker's layer (`FlowBarPresenting.setMeetingPhase`): a phase records (and shows unless a dictation
    /// state covers it); nil ends the meeting chrome and rests the bar.
    public mutating func setMeetingPhase(_ phase: MeetingBarPhase?, now: Date) {
        guard let phase else {
            meetingPhase = nil
            meetingStartedAt = nil
            if case .meeting = state { setState(.resting, now: now) }
            return
        }
        if case .recording(_, let startedAt) = phase { meetingStartedAt = startedAt }
        meetingPhase = phase
        switch state {
        case .meeting, .resting, .hidden: setState(.meeting(phase), now: now)
        default: break
        }
    }

    /// Applies a `FlowBarPresenting.setState`. Meeting chrome is a layer under dictation: `.meeting(…)` records the
    /// phase; dictation states cover it; a later `.resting`/`.hidden` brings the meeting back while it records.
    public mutating func setState(_ new: FlowBarState, now: Date) {
        let previous = state
        var effective = new
        switch new {
        case .meeting(let phase):
            if case .recording(_, let startedAt) = phase { meetingStartedAt = startedAt }
            meetingPhase = phase
        case .resting, .hidden:
            if let phase = meetingPhase { effective = .meeting(phase) }
        default:
            break
        }

        switch effective {
        case .listening(let mode):
            if !previous.isListening { listeningStartedAt = now }
            commandMode = mode == .command
        case .initializing, .processing, .preparing:
            listeningStartedAt = nil
        default:
            listeningStartedAt = nil
            commandMode = false
        }
        if case .transformProcessing = effective {
            if case .transformProcessing = previous {} else { transformStartedAt = now }
        } else {
            transformStartedAt = nil
        }
        state = effective
    }

    // MARK: Cards

    public mutating func show(_ notification: FlowBarNotification, now: Date) {
        if self.notification?.id != notification.id || notificationShownAt == nil { notificationShownAt = now }
        self.notification = notification
    }

    /// Removes the card with this id; false when it wasn't showing.
    @discardableResult public mutating func dismissNotification(id: String) -> Bool {
        guard notification?.id == id else { return false }
        notification = nil; notificationShownAt = nil
        return true
    }

    public mutating func showPrompt(_ prompt: MeetingPrompt, now: Date) {
        self.prompt = prompt; promptShownAt = now
    }

    public mutating func clearPrompt() { prompt = nil; promptShownAt = nil }

    /// The notification whose timeout has run out, if any.
    public func expiredNotification(at now: Date) -> String? {
        guard let notification, let shown = notificationShownAt, let timeout = notification.timeout else { return nil }
        return now.timeIntervalSince(shown) >= timeout ? notification.id : nil
    }

    public func promptExpired(at now: Date) -> Bool {
        guard let prompt, let shown = promptShownAt else { return false }
        return now.timeIntervalSince(shown) >= prompt.timeout
    }

    // MARK: Scene

    /// Whether the resting bar shows now (not snoozed, not turned off).
    public func restingShown(at now: Date) -> Bool { restingVisible && now >= hiddenUntil }

    public func scene(at now: Date) -> FlowBarScene {
        var scene = FlowBarScene()
        scene.edge = edge
        scene.commandMode = commandMode
        scene.languageCode = languageCode
        scene.soundsOn = soundsOn
        scene.pushToTalkShortcut = pushToTalkShortcut
        scene.notification = notification
        scene.notificationShownAt = notificationShownAt
        scene.prompt = prompt
        scene.promptShownAt = promptShownAt
        if let text = liveText, !text.isEmpty { scene.liveText = text }

        switch state {
        case .hidden: scene.pill = .hidden
        case .resting: scene.pill = restingShown(at: now) ? (pointerInside ? .ready : .resting) : .hidden
        case .ready: scene.pill = .ready
        case .initializing: scene.pill = .initializing
        case .listening(let mode):
            scene.pill = mode == .handsFree ? .handsFree(elapsed: floor(now.timeIntervalSince(listeningStartedAt ?? now))) : .pushToTalk
        case .processing: scene.pill = .processing
        case .preparing(let fraction): scene.pill = .preparing(fraction: min(max(fraction, 0), 1))
        case .transformProcessing(let label): scene.pill = .transformProcessing(label: label, startedAt: transformStartedAt ?? now)
        case .transformCompleted: scene.pill = .transformCompleted
        case .cleanupCompleted: scene.pill = .cleanupCompleted
        case .error: scene.pill = .error
        case .meeting(let phase): scene.pill = .meeting(phase, elapsed: meetingStartedAt.map { floor(now.timeIntervalSince($0)) } ?? 0)
        }
        // Hover only means something on what is showing.
        if let hovered, FlowBarModel.elements(in: scene).contains(hovered) { scene.hovered = hovered }
        return scene
    }

    /// The hoverable elements a scene contains (cards included).
    public static func elements(in scene: FlowBarScene) -> Set<FlowBarElement> {
        var set: Set<FlowBarElement> = []
        switch scene.pill {
        case .hidden, .resting: break
        case .ready: set.insert(.pill); FlowBarPicker.allCases.forEach { set.insert(.picker($0)) }
        case .handsFree: set.formUnion([.pill, .cancel, .finish])
        case .meeting(let phase, _):
            set.insert(.meetingBody)
            if phase != .stopping { set.insert(.meetingStop) }
        default: set.insert(.pill)
        }
        if let n = scene.notification {
            n.actions.indices.forEach { set.insert(.cardAction(id: n.id, index: $0)) }
            set.insert(.cardClose(id: n.id))
        }
        if scene.prompt != nil { set.formUnion([.prompt(.record), .prompt(.notNow), .prompt(.neverForApp)]) }
        return set
    }
}

extension FlowBarState {
    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

import Foundation
import Carbon.HIToolbox

// Shortcuts are sets of macOS virtual keycodes (behaviour.md §3.2): left and right modifiers are distinct, Fn is a
// key like any other, mouse buttons are pseudo-keycodes. The event tap in InsertionKit matches chords; this file
// owns the codec, the defaults and the display rules so settings and UI agree.

/// A chord of virtual keycodes, stored as the sorted codes joined with "+" ("63" = Fn, "49+63" = Fn+Space).
public struct KeyChord: Codable, Hashable, Sendable, CustomStringConvertible {
    public static let fn: UInt16 = 63
    public static let capsLock: UInt16 = 57
    public static let mouseMiddle: UInt16 = 4098
    /// Mouse buttons 4…10 are 4099…4105.
    public static func mouseButton(_ n: Int) -> UInt16 { UInt16(4095 + n) }
    public static let mouseAux: UInt16 = 65535
    /// The alias the settings use for "double-tap Fn" as a hands-free trigger.
    public static let doubleFnAlias = "doubleFn"

    public var keys: Set<UInt16>

    public init(_ keys: Set<UInt16>) { self.keys = keys }
    public init(_ keys: UInt16...) { self.keys = Set(keys) }

    /// Parses "49+63"; nil for anything that isn't `+`-joined integers.
    public init?(string: String) {
        var keys: Set<UInt16> = []
        for part in string.split(separator: "+") {
            guard let code = UInt16(part) else { return nil }
            keys.insert(code)
        }
        guard !keys.isEmpty else { return nil }
        self.keys = keys
    }

    public var stringValue: String { keys.sorted().map(String.init).joined(separator: "+") }
    public var description: String { stringValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let chord = KeyChord(string: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad key chord \(raw)"))
        }
        self = chord
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }

    public static let modifierCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_RightCommand), UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Control), UInt16(kVK_RightControl), UInt16(kVK_Shift), UInt16(kVK_RightShift), fn, capsLock,
    ]
    public static func isMouse(_ code: UInt16) -> Bool { code >= mouseMiddle }
    public var hasModifierOrMouse: Bool { keys.contains { KeyChord.modifierCodes.contains($0) || KeyChord.isMouse($0) } }

    /// Display order inside a chord: Fn, Control, Command, Option, Shift, then others (§3.2).
    public static func displayRank(_ code: UInt16) -> Int {
        switch Int(code) {
        case Int(fn): 0
        case kVK_Control, kVK_RightControl: 1
        case kVK_Command, kVK_RightCommand: 2
        case kVK_Option, kVK_RightOption: 3
        case kVK_Shift, kVK_RightShift: 4
        default: 5
        }
    }

    /// Human labels per key ("⌃ Ctrl", "⌘ Cmd →" for the right-hand variant, "Space", "Middle Click", "Mouse 4").
    public static func label(_ code: UInt16) -> String {
        switch Int(code) {
        case Int(fn): return "Fn"
        case kVK_Control: return "⌃ Ctrl"
        case kVK_RightControl: return "⌃ Ctrl →"
        case kVK_Command: return "⌘ Cmd"
        case kVK_RightCommand: return "⌘ Cmd →"
        case kVK_Option: return "⌥ Opt"
        case kVK_RightOption: return "⌥ Opt →"
        case kVK_Shift: return "⇧ Shift"
        case kVK_RightShift: return "⇧ Shift →"
        case Int(capsLock): return "Caps Lock"
        case kVK_Space: return "Space"
        case kVK_Escape: return "Esc"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case Int(mouseMiddle): return "Middle Click"
        case Int(mouseAux): return "Mouse Aux"
        case let c where c > Int(mouseMiddle) && c < Int(mouseAux): return "Mouse \(c - 4095)"
        default: return KeyChord.keyName(code)
        }
    }

    /// "Fn + Space".
    public var displayString: String {
        keys.sorted { (KeyChord.displayRank($0), $0) < (KeyChord.displayRank($1), $1) }.map(KeyChord.label).joined(separator: " + ")
    }

    /// The character a plain keycode types on the current layout, upper-cased; F-keys by name.
    public static func keyName(_ code: UInt16) -> String {
        let special: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
            kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down", kVK_ForwardDelete: "⌦",
        ]
        if let s = special[Int(code)] { return s }
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// What a chord does (behaviour.md §3.1, code values exact).
public enum ShortcutAction: String, Codable, CaseIterable, Sendable {
    case pushToTalk = "ptt"
    case handsFree = "popo"
    case commandMode = "lens"
    case pasteLastText = "paste_last_text"
    case copyLastText = "copy_last_text"
    case dismiss
    case transform = "polish"
    case transformPrompt1 = "polish_prompt_1"
    case transformPrompt2 = "polish_prompt_2"
    case notetaker = "open_meeting_recorder"
    case focusMode = "toggle_focus_mode"
    case openScratchpad = "open_scratchpad"
    case viewDiff = "view_diff"
    case pressEnter = "enter_rebind"

    /// Settings label (§3.1).
    public var title: String {
        switch self {
        case .pushToTalk: "Push to talk"
        case .handsFree: "Hands-free mode"
        case .commandMode: "Command Mode"
        case .pasteLastText: "Paste last transcript"
        case .copyLastText: "Copy last transcript"
        case .dismiss: "Cancel"
        case .transform: "Transform"
        case .transformPrompt1: "Transform 2"
        case .transformPrompt2: "Transform 3"
        case .notetaker: "Join meeting / start Notetaker"
        case .focusMode: "Focus Mode"
        case .openScratchpad: "Open Scratchpad"
        case .viewDiff: "Transform view changes"
        case .pressEnter: "Press Enter"
        }
    }
}

/// The chord → action map, with the macOS defaults (§3.1). Several chords may map to one action.
public struct ShortcutMap: Codable, Hashable, Sendable {
    public var bindings: [KeyChord: ShortcutAction]
    /// Hands-free is also a double-tap of Fn (`doubleFn` alias) when true.
    public var doubleTapFnForHandsFree: Bool

    public init(bindings: [KeyChord: ShortcutAction], doubleTapFnForHandsFree: Bool = true) {
        self.bindings = bindings; self.doubleTapFnForHandsFree = doubleTapFnForHandsFree
    }

    public static let macDefaults = ShortcutMap(bindings: [
        KeyChord(KeyChord.fn): .pushToTalk,
        KeyChord(KeyChord.fn, UInt16(kVK_Space)): .handsFree,
        KeyChord(KeyChord.fn, UInt16(kVK_Control)): .commandMode,
        KeyChord(UInt16(kVK_Control), UInt16(kVK_Command), UInt16(kVK_ANSI_V)): .pasteLastText,
        KeyChord(UInt16(kVK_Control), UInt16(kVK_Command), UInt16(kVK_ANSI_C)): .copyLastText,
        KeyChord(UInt16(kVK_Escape)): .dismiss,
        KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_1)): .transform,
        KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_2)): .transformPrompt1,
        KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_3)): .transformPrompt2,
        KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_M)): .notetaker,
    ])

    /// The alternative when the keyboard has no Fn key (§3.1): Control + Space for push-to-talk.
    public static let noFnKeyboardDefaults = ShortcutMap(bindings: [
        KeyChord(UInt16(kVK_Control), UInt16(kVK_Space)): .pushToTalk,
        KeyChord(UInt16(kVK_Control), UInt16(kVK_Option), UInt16(kVK_Space)): .handsFree,
        KeyChord(UInt16(kVK_Control), UInt16(kVK_Option), UInt16(kVK_Command)): .commandMode,
        KeyChord(UInt16(kVK_Control), UInt16(kVK_Command), UInt16(kVK_ANSI_V)): .pasteLastText,
        KeyChord(UInt16(kVK_Control), UInt16(kVK_Command), UInt16(kVK_ANSI_C)): .copyLastText,
        KeyChord(UInt16(kVK_Escape)): .dismiss,
        KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_1)): .transform,
        KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_M)): .notetaker,
    ], doubleTapFnForHandsFree: false)

    public func chords(for action: ShortcutAction) -> [KeyChord] {
        bindings.filter { $0.value == action }.map(\.key).sorted { $0.stringValue < $1.stringValue }
    }

    /// The maximum number of keys in a chord (§3.2).
    public static let maxKeys = 3

    // Codable through the string form so the stored map reads as {"49+63": "popo"}.
    private enum CodingKeys: String, CodingKey { case bindings, doubleTapFnForHandsFree }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: ShortcutAction].self, forKey: .bindings)
        var bindings: [KeyChord: ShortcutAction] = [:]
        for (key, action) in raw { if let chord = KeyChord(string: key) { bindings[chord] = action } }
        self.bindings = bindings
        doubleTapFnForHandsFree = try container.decodeIfPresent(Bool.self, forKey: .doubleTapFnForHandsFree) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.stringValue, $0.value) }), forKey: .bindings)
        try container.encode(doubleTapFnForHandsFree, forKey: .doubleTapFnForHandsFree)
    }
}

/// What the hotkey monitor reports (§3.3): an action pressed or released, a double or triple tap, Esc.
public enum HotkeyEvent: Equatable, Sendable {
    case pressed(ShortcutAction, KeyChord)
    case released(ShortcutAction, KeyChord)
    /// Fn tapped twice within `DictationLimits.debounceWindow` (hands-free), or three times (Notetaker).
    case doubleTap
    case tripleTap
    /// Another app turned on Secure Keyboard Entry; the tap receives no keys until it is off.
    case secureInput(blocked: Bool, ownerBundleID: String?)
}

import Carbon.HIToolbox
import CoreGraphics

/// Key presses the inserter posts (⌘V, ⌘C, Return, Tab), tagged so the hotkey tap lets them through untouched.
enum SyntheticKeys {
    /// `eventSourceUserData` of every event Super Flow posts ("SFLW").
    static let marker: Int64 = 0x5346_4C57

    /// Posts a key press (down, up) at the HID level carrying exactly `flags`. False when the events can't be made.
    @discardableResult
    static func press(_ code: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

/// Keycodes by character on the user's keyboard layout (behaviour.md §9.1): ⌘V is the key that types "v" with ⌘
/// held. Dvorak puts it on the "." key; "Dvorak – QWERTY ⌘" goes back to QWERTY while ⌘ is down.
public enum KeyboardLayout {
    /// The lowest keycode (0…127) whose translation is `character`; nil when no key types it.
    public static func keyCode(for character: String, translate: (UInt16) -> String?) -> UInt16? {
        (0..<UInt16(128)).first { translate($0)?.lowercased() == character }
    }

    /// The keycode typing `character` with ⌘ held: on the current layout, then on the ASCII-capable one (non-Latin
    /// layouts send shortcuts through it), else the ANSI position. Text Input Sources need the main thread.
    @MainActor static func commandKeyCode(for character: String, ansi: Int) -> CGKeyCode {
        for source in [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()] {
            guard let source = source?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            if let code = keyCode(for: character, translate: { translate($0, layout: layout, modifiers: cmdKey) }) { return code }
        }
        return CGKeyCode(ansi)
    }

    private static func translate(_ code: UInt16, layout: Data, modifiers: Int) -> String? {
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(base, code, UInt16(kUCKeyActionDown), UInt32((modifiers >> 8) & 0xFF), UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

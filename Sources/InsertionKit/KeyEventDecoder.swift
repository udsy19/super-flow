import Carbon.HIToolbox
import CoreGraphics
import SuperFlowCore

/// Turns event-tap events into the KeyChord codes the engine matches (behaviour.md §3.2): key-down/up by virtual
/// keycode, modifiers from `flagsChanged` with left and right told apart, mouse buttons 3…10 as 4098…4105.
public enum KeyEventDecoder {
    /// Device-dependent modifier bits (IOKit `NX_DEVICE…KEYMASK`) per keycode, with the device-independent family bit.
    static let modifierBits: [UInt16: (device: UInt64, family: CGEventFlags)] = [
        UInt16(kVK_Control): (0x0000_0001, .maskControl), UInt16(kVK_RightControl): (0x0000_2000, .maskControl),
        UInt16(kVK_Shift): (0x0000_0002, .maskShift), UInt16(kVK_RightShift): (0x0000_0004, .maskShift),
        UInt16(kVK_Command): (0x0000_0008, .maskCommand), UInt16(kVK_RightCommand): (0x0000_0010, .maskCommand),
        UInt16(kVK_Option): (0x0000_0020, .maskAlternate), UInt16(kVK_RightOption): (0x0000_0040, .maskAlternate),
    ]

    /// The key transition an event stands for; nil for events no chord can contain (left/right clicks, Caps Lock,
    /// whose toggle the OS owns).
    public static func transition(type: CGEventType, keyCode: UInt16, flags: CGEventFlags, mouseButton: Int64) -> (code: UInt16, isDown: Bool)? {
        switch type {
        case .keyDown: return (keyCode, true)
        case .keyUp: return (keyCode, false)
        case .flagsChanged:
            if keyCode == KeyChord.fn { return (keyCode, flags.contains(.maskSecondaryFn)) }
            guard let bits = modifierBits[keyCode] else { return nil }
            // Keyboards that don't report the left/right bits fall back to the family bit.
            let familyDevice = modifierBits.values.filter { $0.family == bits.family }.reduce(UInt64(0)) { $0 | $1.device }
            let isDown = flags.rawValue & familyDevice != 0 ? flags.rawValue & bits.device != 0 : flags.contains(bits.family)
            return (keyCode, isDown)
        case .otherMouseDown, .otherMouseUp:
            guard (2...9).contains(mouseButton) else { return nil }
            return (KeyChord.mouseMiddle + UInt16(mouseButton - 2), type == .otherMouseDown)
        default: return nil
        }
    }

    /// Held modifiers whose family bit is absent from a `flagsChanged` event's flags: they are up even though their
    /// release was missed (tap disabled, secure input). Only clears keys, never adds them: arrow and function keys
    /// carry the Fn bit without Fn being down.
    public static func releasedModifiers(held: some Sequence<UInt16>, flags: CGEventFlags) -> [UInt16] {
        held.filter { code in
            if code == KeyChord.fn { return !flags.contains(.maskSecondaryFn) }
            guard let bits = modifierBits[code] else { return false }
            return !flags.contains(bits.family)
        }.sorted()
    }
}

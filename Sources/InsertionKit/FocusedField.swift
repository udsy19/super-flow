import AppKit
import ApplicationServices

/// Accessibility reads with a short messaging timeout, so a hung app costs at most a quarter of a second.
@MainActor
enum AX {
    static let timeout: Float = 0.25
    private static var exposedPIDs: Set<pid_t> = []

    /// The app's element. Electron apps build their accessibility tree only when asked (`AXManualAccessibility`),
    /// once per process; native apps ignore the attribute.
    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        if exposedPIDs.insert(pid).inserted { _ = set(element, "AXManualAccessibility", kCFBooleanTrue) }
        return element
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let child = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(child, timeout)
        return child
    }

    static func range(_ element: AXUIElement, _ name: String) -> NSRange? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }
}

/// The focused element of the frontmost app, as Accessibility reports it (behaviour.md §6.3, §9).
@MainActor
struct FocusedField {
    let element: AXUIElement
    let role: String?
    let isSecure: Bool
    let isEditable: Bool

    /// nil without Accessibility, or when the app reports no focused element.
    static func current() -> FocusedField? {
        guard AXIsProcessTrusted(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let element = AX.element(AX.application(pid), kAXFocusedUIElementAttribute) else { return nil }
        let role = AX.string(element, kAXRoleAttribute)
        return FocusedField(
            element: element,
            role: role,
            isSecure: FieldRules.isSecure(role: role, subrole: AX.string(element, kAXSubroleAttribute),
                                          secureInputOwner: SecureInput.ownerPID(), targetPID: pid),
            isEditable: FieldRules.isEditable(role: role, valueSettable: AX.isSettable(element, kAXValueAttribute)))
    }

    var value: String? { AX.string(element, kAXValueAttribute) }
    var selectedRange: NSRange? { AX.range(element, kAXSelectedTextRangeAttribute) }
    var selectedText: String? { AX.string(element, kAXSelectedTextAttribute) }

    func isSame(as other: FocusedField) -> Bool { CFEqual(element, other.element) }

    /// Writes `text` over the selection through Accessibility and checks that it landed. Only for elements whose
    /// value reads back, so a write an app accepts but ignores is never taken for an insertion.
    func insert(_ text: String) -> Bool {
        guard !isSecure, let before = value, let selection = selectedRange, AX.isSettable(element, kAXSelectedTextAttribute),
              AX.set(element, kAXSelectedTextAttribute, text as CFString) else { return false }
        return FieldRules.didInsert(text, before: before, selection: selection, after: value)
    }
}

/// The rules about the focused element, as pure logic.
public enum FieldRules {
    public static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// Never dictate into a password field (behaviour.md §9.8): the element is a secure text field (role or subrole),
    /// or the target app itself holds Secure Keyboard Entry (a password prompt in a terminal). Secure input left on
    /// by another app (a password manager) does not make the target secure.
    public static func isSecure(role: String?, subrole: String?, secureInputOwner: pid_t?, targetPID: pid_t?) -> Bool {
        if role == kAXSecureTextFieldSubrole || subrole == kAXSecureTextFieldSubrole { return true }
        guard let secureInputOwner, let targetPID else { return false }
        return secureInputOwner == targetPID
    }

    public static func isEditable(role: String?, valueSettable: Bool) -> Bool {
        valueSettable || role.map(textRoles.contains) == true
    }

    /// Whether a field went from `before` to `after` by `text` replacing `selection` (a UTF-16 range): exactly, or
    /// at least changed and now containing the text (fields that reformat on input).
    public static func didInsert(_ text: String, before: String, selection: NSRange, after: String?) -> Bool {
        guard let after, after != before else { return false }
        let value = before as NSString
        if selection.location >= 0, NSMaxRange(selection) <= value.length,
           after == value.replacingCharacters(in: selection, with: text) { return true }
        return after.contains(text)
    }
}

/// The text around the caret that context awareness passes on (behaviour.md §6.3), at most `limit` characters
/// around the caret: up to a fifth of it after the caret (enough to join the next word), the rest before it, which
/// is what spelling and continuation use. The selection is capped at `limit` as well.
public struct TextWindow: Equatable {
    public var before: String
    public var selected: String
    public var after: String

    public init(before: String, selected: String, after: String) {
        self.before = before; self.selected = selected; self.after = after
    }

    /// `selection` is a UTF-16 range as Accessibility reports it; nil puts the caret at the end.
    public init(value: String, selection: NSRange?, limit: Int) {
        let text = value as NSString
        let location = min(max(selection?.location ?? text.length, 0), text.length)
        let length = min(max(selection?.length ?? 0, 0), text.length - location)
        let fullBefore = text.substring(to: location)
        let fullAfter = text.substring(from: location + length)
        let afterReserve = min(fullAfter.count, limit / 5)
        let beforeCount = min(fullBefore.count, limit - afterReserve)
        before = String(fullBefore.suffix(beforeCount))
        after = String(fullAfter.prefix(limit - beforeCount))
        selected = String(text.substring(with: NSRange(location: location, length: length)).prefix(limit))
    }
}

/// Follows the inserted text while the user edits it (behaviour.md §9.4): the text is found again between the
/// characters that surrounded it, and whatever stands there now is the edited version.
public struct EditTracker: Equatable {
    public static let anchorLength = 24

    public let inserted: String
    private let prefix: String
    private let suffix: String
    /// The latest version that differs from the inserted text; nil while unchanged or changed back.
    public private(set) var edited: String?

    /// Finds `inserted` in the field's value: the occurrence ending at the caret (a UTF-16 offset) when that fits,
    /// else the last one. nil when the text isn't there.
    public init?(value: String, inserted: String, caret: Int?) {
        guard !inserted.isEmpty else { return nil }
        let text = value as NSString
        let length = (inserted as NSString).length
        var found = NSRange(location: NSNotFound, length: 0)
        if let caret, caret >= length, caret <= text.length,
           text.substring(with: NSRange(location: caret - length, length: length)) == inserted {
            found = NSRange(location: caret - length, length: length)
        } else {
            found = text.range(of: inserted, options: .backwards)
        }
        guard found.location != NSNotFound else { return nil }
        self.inserted = inserted
        prefix = String(text.substring(to: found.location).suffix(Self.anchorLength))
        suffix = String(text.substring(from: NSMaxRange(found)).prefix(Self.anchorLength))
    }

    /// Reads the field again. Values where the surrounding text is gone (the user moved on, the message was sent,
    /// the field emptied) are ignored, so the last edit seen stays. Typing on after or before the inserted text is
    /// not an edit of it.
    public mutating func observe(_ value: String) {
        guard let current = Self.text(between: prefix, and: suffix, in: value),
              !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let unchanged = current == inserted || (suffix.isEmpty && current.hasPrefix(inserted)) || (prefix.isEmpty && current.hasSuffix(inserted))
        edited = unchanged ? nil : current
    }

    private static func text(between prefix: String, and suffix: String, in value: String) -> String? {
        var start = value.startIndex
        if !prefix.isEmpty {
            guard let match = value.range(of: prefix) else { return nil }
            start = match.upperBound
        }
        var end = value.endIndex
        if !suffix.isEmpty {
            guard let match = value.range(of: suffix, range: start..<value.endIndex) else { return nil }
            end = match.lowerBound
        }
        return String(value[start..<end])
    }
}

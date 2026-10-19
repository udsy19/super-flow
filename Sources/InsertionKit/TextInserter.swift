import AppKit
import Carbon.HIToolbox
import SuperFlowCore

/// TextInserting (behaviour.md §9). Paste first: the text goes on the pasteboard as a lazily provided item, ⌘V is
/// posted for the key that types "v" on the user's layout, and the target reading the item is the proof the paste
/// landed; the user's clipboard comes back afterwards, whether or not the paste landed (the caller keeps the words in
/// History). When the target never reads it, an Accessibility write over the selection is the fallback (or the first
/// try with `InsertionMethod.accessibility`). Password fields are never written. Without Accessibility nothing can be
/// pasted for the user, so the text is put on the clipboard for them to paste.
///
/// `notInserted` reasons are diagnostic codes in the style of §9.3 (`no_focused_element`,
/// `paste_not_picked_up`, `accessibility_not_trusted`, `event_post_failed`), not user-facing copy.
@MainActor
final class TextInserter: TextInserting {
    static let shared = TextInserter()

    /// Paste timings (behaviour.md §22.4 #5): no read within `readTimeout` means the paste failed; the old clipboard
    /// returns `restoreDelay` after ⌘V, and never sooner than `readGrace` after the target's first read, so apps
    /// that read several flavours get them all.
    private enum Timing {
        static let readTimeout: TimeInterval = 0.6
        static let restoreDelay: TimeInterval = 0.5
        static let readGrace: TimeInterval = 0.15
        /// How long a paste waits for the user to let go of ⌘⌃⌥⇧ (a held ⌃⌘ would turn ⌘V into ⌃⌘V).
        static let modifierWait: TimeInterval = 0.4
        static let copyTimeout: TimeInterval = 0.3
        static let actionDelay: TimeInterval = 0.05
        static let editPoll: TimeInterval = 0.5
        static let poll: TimeInterval = 0.01
    }

    func insert(_ text: String, actions: [PostInsertAction], method: InsertionMethod) async -> InsertionOutcome {
        let field = FocusedField.current()
        if field?.isSecure == true || SecureInput.isHeldByFrontmostApp { return .blockedSecureField }
        guard AXIsProcessTrusted() else {
            if !text.isEmpty { copyToClipboard(text) }
            return .notInserted(reason: "accessibility_not_trusted")
        }
        if !text.isEmpty, !(method == .accessibility && field?.insert(text) == true),
           let reason = await paste(text, fallback: method == .paste ? field : nil) {
            return .notInserted(reason: reason)
        }
        for action in actions {
            await Self.sleep(Timing.actionDelay)
            SyntheticKeys.press(CGKeyCode(action == .pressReturn ? kVK_Return : kVK_Tab))
        }
        return .inserted
    }

    func selectedText() async -> String? {
        guard AXIsProcessTrusted(), !SecureInput.isHeldByFrontmostApp else { return nil }
        let field = FocusedField.current()
        if field?.isSecure == true { return nil }
        if let text = field?.selectedText, !text.isEmpty { return text }
        // Accessibility knows the selection: an empty one means nothing is selected (⌘C would copy a whole line in
        // some editors).
        if let field, let range = field.selectedRange {
            guard range.length > 0, let value = field.value, NSMaxRange(range) <= (value as NSString).length else { return nil }
            return (value as NSString).substring(with: range)
        }
        return await selectedTextViaCopy()
    }

    func replaceSelection(with text: String) async -> InsertionOutcome {
        await insert(text, actions: [], method: Defaults[.insertionMethod])
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func observeEdits(of insertedText: String, window: TimeInterval) async -> String? {
        guard let field = FocusedField.current(), !field.isSecure, let value = field.value,
              var tracker = EditTracker(value: value, inserted: insertedText, caret: field.selectedRange?.location) else { return nil }
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline, !Task.isCancelled {
            await Self.sleep(Timing.editPoll)
            guard let current = FocusedField.current(), current.isSame(as: field), let value = current.value else { break }
            tracker.observe(value)
        }
        return tracker.edited
    }

    // MARK: - Paste

    /// Pastes `text`; nil when it landed, else why not. Either way the user's clipboard ends as it was (unless
    /// restoring is off).
    private func paste(_ text: String, fallback field: FocusedField?) async -> String? {
        let swap = PasteboardSwap(text: text, restoring: Defaults[.restoreClipboardAfterPaste])
        await waitForModifierRelease()
        let pastedAt = Date()
        guard SyntheticKeys.press(KeyboardLayout.commandKeyCode(for: "v", ansi: kVK_ANSI_V), flags: .maskCommand) else {
            swap.finish()
            return "event_post_failed"
        }
        while !swap.wasRead, Date().timeIntervalSince(pastedAt) < Timing.readTimeout { await Self.sleep(Timing.poll) }
        guard swap.wasRead else {
            // Take the text off first so a late ⌘V can't paste it a second time.
            swap.withdraw()
            let inserted = field?.insert(text) == true
            swap.finish()
            return inserted ? nil : field == nil ? "no_focused_element" : "paste_not_picked_up"
        }
        let readAt = Date()
        await Self.sleep(max(Timing.restoreDelay - readAt.timeIntervalSince(pastedAt), Timing.readGrace))
        swap.finish()
        return nil
    }

    private func waitForModifierRelease() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let deadline = Date().addingTimeInterval(Timing.modifierWait)
        while !CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty, Date() < deadline {
            await Self.sleep(Timing.poll)
        }
    }

    /// The copy-based fallback (§10.1) for apps whose selection Accessibility can't see: ⌘C, read, put the user's
    /// clipboard back.
    private func selectedTextViaCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(of: pasteboard)
        let before = pasteboard.changeCount
        guard SyntheticKeys.press(KeyboardLayout.commandKeyCode(for: "c", ansi: kVK_ANSI_C), flags: .maskCommand) else { return nil }
        let start = Date()
        while pasteboard.changeCount == before, Date().timeIntervalSince(start) < Timing.copyTimeout { await Self.sleep(Timing.poll) }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        saved.restore(to: pasteboard)
        return text?.isEmpty == false ? text : nil
    }

    private static func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
    }
}

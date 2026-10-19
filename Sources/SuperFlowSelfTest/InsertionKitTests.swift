import AppKit
import Carbon.HIToolbox
import SuperFlowCore
import InsertionKit

func registerInsertionKitTests() {
    SelfTest.cases.append(("InsertionKit.fnGestures", { insertionFnGestures() }))
    SelfTest.cases.append(("InsertionKit.chords", { insertionChords() }))
    SelfTest.cases.append(("InsertionKit.staleKeys", { insertionStaleKeys() }))
    SelfTest.cases.append(("InsertionKit.keyDecoding", { insertionKeyDecoding() }))
    SelfTest.cases.append(("InsertionKit.pasteboard", { MainActor.assumeIsolated { insertionPasteboard() } }))
    SelfTest.cases.append(("InsertionKit.secureFields", { insertionSecureFields() }))
    SelfTest.cases.append(("InsertionKit.textWindow", { insertionTextWindow() }))
    SelfTest.cases.append(("InsertionKit.editTracker", { insertionEditTracker() }))
    SelfTest.cases.append(("InsertionKit.keyboardLayout", { insertionKeyboardLayout() }))
    SelfTest.cases.append(("InsertionKit.appCategories", { insertionAppCategories() }))
    SelfTest.cases.append(("InsertionKit.fnKeyboard", { insertionFnKeyboard() }))
}

private let fn = KeyChord.fn
private let space = UInt16(kVK_Space)
private let control = UInt16(kVK_Control)
private let command = UInt16(kVK_Command)
private let option = UInt16(kVK_Option)
private let fnChord = KeyChord(KeyChord.fn)

/// Drives a `ChordEngine` with a scripted timeline; `physicallyDown` stands in for the HID state.
private struct Keys {
    var engine: ChordEngine
    var physicallyDown: (UInt16) -> Bool = { _ in true }

    init(_ map: ShortcutMap = .macDefaults) { engine = ChordEngine(map: map) }

    mutating func down(_ code: UInt16, _ time: TimeInterval) -> ChordDecision {
        engine.handle(code, isDown: true, at: time, isPhysicallyDown: physicallyDown)
    }
    mutating func up(_ code: UInt16, _ time: TimeInterval) -> ChordDecision {
        engine.handle(code, isDown: false, at: time, isPhysicallyDown: physicallyDown)
    }
    /// Down then up; the events of both.
    mutating func tap(_ code: UInt16, _ time: TimeInterval, hold: TimeInterval = 0.1) -> [HotkeyEvent] {
        down(code, time).events + up(code, time + hold).events
    }
}

private func insertionFnGestures() {
    var keys = Keys()
    let press = keys.down(fn, 0)
    check(press.events == [.pressed(.pushToTalk, fnChord)] && !press.swallow, "Fn down starts push-to-talk, Fn reaches the app")
    check(keys.up(fn, 2).events == [.released(.pushToTalk, fnChord)], "Fn up after a hold releases push-to-talk")

    keys = Keys()
    check(keys.tap(fn, 10) == [.pressed(.pushToTalk, fnChord), .released(.pushToTalk, fnChord)], "first tap is an ordinary press and release")
    check(keys.down(fn, 10.5).events == [.doubleTap], "second press within 500 ms of the release is a double tap")
    check(keys.up(fn, 10.6).events.isEmpty, "the double tap's release reports nothing")
    check(keys.down(fn, 11.0).events == [.tripleTap], "third press within the window is a triple tap")
    check(keys.up(fn, 11.1).events.isEmpty, "the triple tap's release reports nothing")
    check(keys.down(fn, 11.3).events == [.pressed(.pushToTalk, fnChord)], "a fourth press starts over")

    keys = Keys()
    _ = keys.tap(fn, 20)
    check(keys.down(fn, 20.7).events == [.pressed(.pushToTalk, fnChord)], "600 ms after the release is too slow for a double tap")

    keys = Keys()
    _ = keys.tap(fn, 30, hold: 0.8)
    check(keys.down(fn, 30.9).events == [.pressed(.pushToTalk, fnChord)], "a hold longer than the window is not a tap")

    keys = Keys()
    _ = keys.tap(fn, 40)
    _ = keys.tap(UInt16(kVK_ANSI_A), 40.2)
    check(keys.down(fn, 40.3).events == [.pressed(.pushToTalk, fnChord)], "typing between taps breaks the sequence")

    keys = Keys()
    _ = keys.down(fn, 50)
    let delete = keys.down(UInt16(kVK_Delete), 50.05)
    check(delete.events == [.otherKey(during: .pushToTalk, fnChord)] && !delete.swallow,
          "Fn+Delete is no chord: forward delete reaches the app and the other key is reported once")
    check(keys.down(UInt16(kVK_ANSI_A), 50.06).events.isEmpty, "a second other key is not reported again")
    _ = keys.up(UInt16(kVK_ANSI_A), 50.07)
    _ = keys.up(UInt16(kVK_Delete), 50.08)
    _ = keys.up(fn, 50.1)
    check(keys.down(fn, 50.3).events == [.pressed(.pushToTalk, fnChord)], "a press with another key in it is not a tap")

    var noDouble = ShortcutMap.macDefaults
    noDouble.doubleTapFnForHandsFree = false
    keys = Keys(noDouble)
    _ = keys.tap(fn, 60)
    check(keys.tap(fn, 60.3) == [.pressed(.pushToTalk, fnChord), .released(.pushToTalk, fnChord)], "double tap off: the second tap is a press")
    check(keys.down(fn, 60.6).events == [.tripleTap], "triple tap still reported (the coordinator gates it)")

    keys = Keys(.noFnKeyboardDefaults)
    let ctrlSpace = KeyChord(control, space)
    _ = keys.down(control, 70)
    check(keys.tap(space, 70.1) == [.pressed(.pushToTalk, ctrlSpace), .released(.pushToTalk, ctrlSpace)], "⌃Space push-to-talk")
    check(keys.down(space, 70.4).events == [.pressed(.pushToTalk, ctrlSpace)], "double-tap Fn applies to Fn only")
}

private func insertionChords() {
    var keys = Keys()
    let fnSpace = KeyChord(fn, space)
    _ = keys.down(fn, 0)
    let spaceDown = keys.down(space, 0.1)
    check(spaceDown.events == [.pressed(.handsFree, fnSpace)] && spaceDown.swallow, "Fn then Space: hands-free, Space swallowed")
    let spaceUp = keys.up(space, 0.2)
    check(spaceUp.events == [.released(.handsFree, fnSpace)] && spaceUp.swallow, "Space up releases hands-free and is swallowed")
    let fnUp = keys.up(fn, 0.3)
    check(fnUp.events.isEmpty && !fnUp.swallow, "Fn up after the chord reports nothing")

    keys = Keys()
    let early = keys.down(space, 1)
    check(early.events.isEmpty && !early.swallow, "a lone Space types a space")
    let late = keys.down(fn, 1.1)
    check(late.events == [.pressed(.handsFree, fnSpace)] && !late.swallow, "Space then Fn also matches, Fn is never swallowed")

    keys = Keys()
    _ = keys.down(fn, 2)
    let ctrl = keys.down(control, 2.1)
    check(ctrl.events == [.pressed(.commandMode, KeyChord(fn, control))] && !ctrl.swallow, "Fn+Ctrl: Command Mode, no key swallowed")
    check(keys.up(control, 2.5).events == [.released(.commandMode, KeyChord(fn, control))], "Command Mode release")

    keys = Keys()
    let optionM = KeyChord(option, UInt16(kVK_ANSI_M))
    check(keys.down(option, 3).events.isEmpty, "⌥ alone is nothing")
    let m = keys.down(UInt16(kVK_ANSI_M), 3.1)
    check(m.events == [.pressed(.notetaker, optionM)] && m.swallow, "⌥M: Notetaker, M swallowed")
    let repeatM = keys.down(UInt16(kVK_ANSI_M), 3.2)
    check(repeatM.events.isEmpty && repeatM.swallow, "auto-repeat of a swallowed key is swallowed, no second press")
    let mUp = keys.up(UInt16(kVK_ANSI_M), 3.3)
    check(mUp.events == [.released(.notetaker, optionM)] && mUp.swallow, "M up swallowed")

    keys = Keys()
    let pasteLast = KeyChord(control, command, UInt16(kVK_ANSI_V))
    _ = keys.down(control, 4)
    _ = keys.down(command, 4.01)
    check(keys.down(UInt16(kVK_ANSI_V), 4.02).events == [.pressed(.pasteLastText, pasteLast)], "⌃⌘V paste last")
    check(keys.up(UInt16(kVK_ANSI_V), 4.1).events.isEmpty && keys.up(control, 4.15).events.isEmpty, "paste-last waits while ⌃⌘ are held")
    check(keys.up(command, 4.2).events == [.released(.pasteLastText, pasteLast)], "paste-last releases once every key is up")

    keys = Keys()
    let esc = keys.down(UInt16(kVK_Escape), 5)
    check(esc.events == [.pressed(.dismiss, KeyChord(UInt16(kVK_Escape)))] && !esc.swallow, "Esc dismisses and still reaches the app")
    keys = Keys()
    _ = keys.down(fn, 6)
    check(keys.down(UInt16(kVK_Escape), 6.2).events == [.pressed(.dismiss, KeyChord(UInt16(kVK_Escape)))], "Esc with Fn held still dismisses")

    keys = Keys()
    check(keys.tap(UInt16(kVK_ANSI_A), 7).isEmpty && !keys.down(UInt16(kVK_ANSI_A), 7.5).swallow, "typing is never touched")

    // Chord upgrade (§3.3.3): a larger chord of the same action continues without a new press.
    keys = Keys(ShortcutMap(bindings: [fnChord: .pushToTalk, KeyChord(fn, UInt16(kVK_Shift)): .pushToTalk]))
    _ = keys.down(fn, 8)
    check(keys.down(UInt16(kVK_Shift), 8.2).events.isEmpty, "upgrade fires nothing new")
    check(keys.up(UInt16(kVK_Shift), 8.4).events == [.released(.pushToTalk, KeyChord(fn, UInt16(kVK_Shift)))], "release reports the upgraded chord")

    keys = Keys()
    _ = keys.down(fn, 9)
    check(keys.down(fn, 12).events == [.released(.pushToTalk, fnChord), .pressed(.pushToTalk, fnChord)],
          "a modifier down while held means its up was missed: release, then press again")

    let mouse4 = KeyChord(KeyChord.mouseButton(4))
    keys = Keys(ShortcutMap(bindings: [mouse4: .pressEnter]))
    let click = keys.down(KeyChord.mouseButton(4), 10)
    check(click.events == [.pressed(.pressEnter, mouse4)] && click.swallow && keys.up(KeyChord.mouseButton(4), 10.1).swallow,
          "mouse-button chord fires and the button is swallowed")

    keys = Keys()
    keys.engine.isRecording = true
    check(keys.down(fn, 11).events.isEmpty && keys.down(space, 11.1).swallow, "recorder: no actions, non-modifiers swallowed")
    check(keys.up(space, 11.2).recorded == nil, "recorder waits for every key to come up")
    let recorded = keys.up(fn, 11.3)
    check(recorded.recorded == fnSpace && recorded.events.isEmpty, "recorder captures Fn+Space")
    keys.engine.isRecording = false
    check(keys.down(fn, 12).events == [.pressed(.pushToTalk, fnChord)], "actions resume after the recorder closes")
}

private func insertionStaleKeys() {
    var keys = Keys()
    _ = keys.down(fn, 0)
    let up: (UInt16) -> Bool = { _ in false }
    check(keys.engine.sweep(at: 5, isPhysicallyDown: up).events.isEmpty, "keys held under 10 s survive the sweep")
    check(keys.engine.sweep(at: 11, isPhysicallyDown: { _ in true }).events.isEmpty, "a key the OS still sees down stays")
    check(keys.engine.sweep(at: 11, isPhysicallyDown: up).events == [.released(.pushToTalk, fnChord)], "a stale Fn past 10 s is released")
    check(keys.engine.held.isEmpty, "and dropped")

    keys = Keys()
    _ = keys.down(fn, 0)
    check(keys.engine.sweep(at: 0.5, all: true, isPhysicallyDown: up).events == [.released(.pushToTalk, fnChord)],
          "after the tap is re-enabled every held key is re-checked")

    keys = Keys()
    _ = keys.down(option, 0)
    keys.physicallyDown = { $0 != option }
    check(keys.down(UInt16(kVK_ANSI_M), 3).events.isEmpty, "a key held over 2.5 s that the OS says is up doesn't complete a chord")
    keys = Keys()
    _ = keys.down(option, 0)
    check(keys.down(UInt16(kVK_ANSI_M), 3).events == [.pressed(.notetaker, KeyChord(option, UInt16(kVK_ANSI_M)))], "verified keys still match")
}

private func insertionKeyDecoding() {
    func decode(_ type: CGEventType, _ code: Int, _ flags: CGEventFlags = [], button: Int64 = 0) -> [UInt16] {
        guard let key = KeyEventDecoder.transition(type: type, keyCode: UInt16(code), flags: flags, mouseButton: button) else { return [] }
        return [key.code, key.isDown ? 1 : 0]
    }
    check(decode(.keyDown, kVK_ANSI_M) == [UInt16(kVK_ANSI_M), 1] && decode(.keyUp, kVK_ANSI_M) == [UInt16(kVK_ANSI_M), 0], "key down/up")
    check(decode(.flagsChanged, Int(fn), .maskSecondaryFn) == [fn, 1] && decode(.flagsChanged, Int(fn)) == [fn, 0], "Fn from its flag")
    let leftCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
    let rightCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
    check(decode(.flagsChanged, kVK_Command, leftCmd) == [command, 1], "left ⌘ down")
    check(decode(.flagsChanged, kVK_Command, rightCmd) == [command, 0], "left ⌘ up while right ⌘ stays down")
    check(decode(.flagsChanged, kVK_RightCommand, rightCmd) == [UInt16(kVK_RightCommand), 1], "right ⌘ is its own key")
    check(decode(.flagsChanged, kVK_RightOption, .maskAlternate) == [UInt16(kVK_RightOption), 1], "no left/right bits: the family bit decides")
    check(decode(.flagsChanged, kVK_CapsLock, .maskAlphaShift).isEmpty, "Caps Lock's toggle is the OS's")
    check(decode(.otherMouseDown, 0, button: 2) == [KeyChord.mouseMiddle, 1] && decode(.otherMouseUp, 0, button: 3) == [KeyChord.mouseButton(4), 0],
          "middle click 4098, button 4 is 4099")
    check(decode(.otherMouseDown, 0, button: 1).isEmpty && decode(.leftMouseDown, 0).isEmpty, "left and right clicks are never chord keys")

    check(KeyEventDecoder.releasedModifiers(held: [fn, command, UInt16(kVK_ANSI_A)], flags: []) == [command, fn], "missing flags release held modifiers")
    check(KeyEventDecoder.releasedModifiers(held: [fn, command], flags: [.maskSecondaryFn, .maskCommand]).isEmpty, "present flags keep them")
    check(KeyEventDecoder.releasedModifiers(held: [UInt16(kVK_ANSI_A)], flags: []).isEmpty, "ordinary keys are left alone")
}

@MainActor
private func insertionPasteboard() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.udsy.superflow.selftest.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let custom = NSPasteboard.PasteboardType("com.udsy.superflow.selftest.custom")
    let rich = NSPasteboardItem()
    rich.setString("Hello", forType: .string)
    rich.setString("<b>Hello</b>", forType: .html)
    rich.setData(Data([0, 1, 2, 255]), forType: custom)
    let second = NSPasteboardItem()
    second.setData(Data("two".utf8), forType: custom)
    pasteboard.clearContents()
    pasteboard.writeObjects([rich, second])

    let original = PasteboardSnapshot(of: pasteboard)
    check(original.items.count == 2 && original.items[0].count >= 3, "snapshot keeps every item and every type")
    pasteboard.clearContents()
    pasteboard.setString("something else", forType: .string)
    original.restore(to: pasteboard)
    check(PasteboardSnapshot(of: pasteboard) == original, "restore brings back every item, type and byte")
    check(pasteboard.string(forType: .html) == "<b>Hello</b>" && pasteboard.pasteboardItems?.last?.data(forType: custom) == Data("two".utf8),
          "rich text and private types survive")

    let swap = PasteboardSwap(text: "dictated", pasteboard: pasteboard, restoring: true)
    let types = pasteboard.pasteboardItems?.first?.types ?? []
    check(PasteboardSwap.markerTypes.allSatisfy { types.contains($0) }, "transient, concealed and own markers are set")
    check(!swap.wasRead, "nothing has read the text yet")
    check(pasteboard.string(forType: .string) == "dictated" && swap.wasRead, "the target's read is noticed")
    check(swap.restore() && PasteboardSnapshot(of: pasteboard) == original, "the user's clipboard comes back")

    let overtaken = PasteboardSwap(text: "dictated", pasteboard: pasteboard, restoring: true)
    pasteboard.clearContents()
    pasteboard.setString("copied meanwhile", forType: .string)
    check(!overtaken.restore() && !overtaken.keepText() && pasteboard.string(forType: .string) == "copied meanwhile",
          "a newer copy is never overwritten")

    original.restore(to: pasteboard)
    let failed = PasteboardSwap(text: "dictated", pasteboard: pasteboard, restoring: true)
    failed.withdraw()
    check(pasteboard.string(forType: .string) == nil && !failed.wasRead, "withdrawn text can't be pasted late")
    check(failed.finish() && PasteboardSnapshot(of: pasteboard) == original, "a failed paste gives the user's clipboard back")
    let posted = PasteboardSwap(text: "dictated", pasteboard: pasteboard, restoring: true)
    _ = pasteboard.string(forType: .string)
    check(posted.finish() && PasteboardSnapshot(of: pasteboard) == original, "so does one that landed")
    let copiedAfter = PasteboardSwap(text: "dictated", pasteboard: pasteboard, restoring: true)
    copiedAfter.withdraw()
    pasteboard.clearContents()
    pasteboard.setString("copied meanwhile", forType: .string)
    check(!copiedAfter.finish() && pasteboard.string(forType: .string) == "copied meanwhile", "finishing never overwrites a newer copy")
    check(failed.keepText() == false, "a finished swap is no longer current")
    original.restore(to: pasteboard)

    // A swap's lazy item never outlives it: every path ends by replacing the contents.
    let kept = PasteboardSwap(text: "kept", pasteboard: pasteboard, restoring: false)
    check(!(pasteboard.pasteboardItems?.first?.types ?? []).contains(PasteboardSwap.markerTypes[0]), "no transient markers when not restoring")
    check(kept.finish() && pasteboard.string(forType: .string) == "kept", "not restoring: the text stays")
    check(!(pasteboard.pasteboardItems?.first?.types ?? []).contains(PasteboardSwap.markerTypes[0]), "left text is a plain, lasting copy")

    pasteboard.clearContents()
    let empty = PasteboardSnapshot(of: pasteboard)
    let onEmpty = PasteboardSwap(text: "x", pasteboard: pasteboard, restoring: true)
    check(onEmpty.restore() && empty.items.isEmpty && (pasteboard.pasteboardItems ?? []).isEmpty, "an empty clipboard is restored empty")
}

private func insertionSecureFields() {
    let pid: pid_t = 4242
    check(FieldRules.isSecure(role: "AXSecureTextField", subrole: nil, secureInputOwner: nil, targetPID: pid), "secure role")
    check(FieldRules.isSecure(role: "AXTextField", subrole: "AXSecureTextField", secureInputOwner: nil, targetPID: pid), "secure subrole (web password inputs)")
    check(!FieldRules.isSecure(role: "AXTextField", subrole: nil, secureInputOwner: nil, targetPID: pid), "plain text field")
    check(FieldRules.isSecure(role: "AXTextArea", subrole: nil, secureInputOwner: pid, targetPID: pid), "the target holds secure input (password prompt)")
    check(!FieldRules.isSecure(role: "AXTextArea", subrole: nil, secureInputOwner: 99, targetPID: pid), "secure input left on by another app doesn't block")
    check(FieldRules.isSecure(role: nil, subrole: nil, secureInputOwner: pid, targetPID: pid) && !FieldRules.isSecure(role: nil, subrole: nil, secureInputOwner: pid, targetPID: nil),
          "without a field the owner still decides; no target, no match")

    check(FieldRules.isEditable(role: "AXTextArea", valueSettable: false) && FieldRules.isEditable(role: "AXGroup", valueSettable: true), "editable")
    check(!FieldRules.isEditable(role: "AXStaticText", valueSettable: false) && !FieldRules.isEditable(role: nil, valueSettable: false), "not editable")

    check(FieldRules.didInsert(" big", before: "Hello world", selection: NSRange(location: 5, length: 0), after: "Hello big world"), "caret insertion verified")
    check(FieldRules.didInsert("there", before: "Hello world", selection: NSRange(location: 6, length: 5), after: "Hello there"), "selection replaced")
    check(!FieldRules.didInsert("x", before: "abc", selection: NSRange(location: 3, length: 0), after: "abc"), "an ignored write is not an insertion")
    check(!FieldRules.didInsert("x", before: "abc", selection: NSRange(location: 3, length: 0), after: nil), "unreadable value")
    check(FieldRules.didInsert("ok", before: "a", selection: NSRange(location: 9, length: 0), after: "a ok"), "reformatting field still counts")
}

private func insertionTextWindow() {
    let small = TextWindow(value: "Hello brave world", selection: NSRange(location: 6, length: 5), limit: 500)
    check(small == TextWindow(before: "Hello ", selected: "brave", after: " world"), "split around the selection")
    check(TextWindow(value: "abc", selection: nil, limit: 500) == TextWindow(before: "abc", selected: "", after: ""), "no selection: caret at the end")
    check(TextWindow(value: "abc", selection: NSRange(location: 9, length: 4), limit: 500) == TextWindow(before: "abc", selected: "", after: ""), "out-of-range clamps")

    let long = String(repeating: "a", count: 600) + String(repeating: "b", count: 600)
    let window = TextWindow(value: long, selection: NSRange(location: 600, length: 0), limit: 500)
    check(window.before == String(repeating: "a", count: 400) && window.after == String(repeating: "b", count: 100), "500 chars: 400 before, 100 after")
    let atEnd = TextWindow(value: long, selection: NSRange(location: 1200, length: 0), limit: 500)
    check(atEnd.before.count == 500 && atEnd.after.isEmpty, "caret at the end: all 500 before")
    let shortBefore = TextWindow(value: "ab" + String(repeating: "c", count: 900), selection: NSRange(location: 2, length: 0), limit: 500)
    check(shortBefore.before == "ab" && shortBefore.after.count == 498, "short text before: the rest goes after")
    let emoji = TextWindow(value: "hi 👋 there", selection: NSRange(location: 5, length: 0), limit: 500)
    check(emoji.before == "hi 👋" && emoji.after == " there", "UTF-16 offsets from Accessibility")
}

private func insertionEditTracker() {
    let value = "Hi Sam, see you tomorow at noon. Bye"
    var tracker = EditTracker(value: value, inserted: "see you tomorow at noon.", caret: 32)
    check(tracker != nil, "finds the inserted text at the caret")
    tracker?.observe(value)
    check(tracker?.edited == nil, "unchanged")
    tracker?.observe("Hi Sam, see you tomorrow at noon. Bye")
    check(tracker?.edited == "see you tomorrow at noon.", "the edit is captured")
    tracker?.observe("")
    check(tracker?.edited == "see you tomorrow at noon.", "an emptied field (message sent) keeps the last edit")
    tracker?.observe("Hi Sam, see you tomorow at noon. Bye")
    check(tracker?.edited == nil, "changed back")

    var whole = EditTracker(value: "draft text", inserted: "draft text", caret: nil)
    whole?.observe("draft text and more I typed")
    check(whole?.edited == nil, "typing on after the dictation is not an edit")
    whole?.observe("drafted text")
    check(whole?.edited == "drafted text", "edit of a field that holds only the dictation")

    var repeated = EditTracker(value: "ok ok", inserted: "ok", caret: 2)
    repeated?.observe("okay ok")
    check(repeated?.edited == "okay", "the occurrence at the caret, not the last one")
    check(EditTracker(value: "abc", inserted: "zzz", caret: nil) == nil && EditTracker(value: "abc", inserted: "", caret: nil) == nil, "nothing to follow")
}

private func insertionKeyboardLayout() {
    let qwerty: [UInt16: String] = [0: "a", 8: "c", 9: "v", 47: "."]
    let dvorak: [UInt16: String] = [0: "a", 9: "k", 34: "c", 47: "v"]
    check(KeyboardLayout.keyCode(for: "v", translate: { qwerty[$0] }) == UInt16(kVK_ANSI_V), "QWERTY V")
    check(KeyboardLayout.keyCode(for: "v", translate: { dvorak[$0] }) == UInt16(kVK_ANSI_Period), "Dvorak V is on the period key")
    check(KeyboardLayout.keyCode(for: "c", translate: { dvorak[$0] }) == UInt16(kVK_ANSI_I), "Dvorak C")
    check(KeyboardLayout.keyCode(for: "v", translate: { ["м", "и"][Int($0) % 2] }) == nil, "no key types it")
    check(KeyboardLayout.keyCode(for: "v", translate: { $0 == 9 ? "V" : nil }) == UInt16(kVK_ANSI_V), "case-insensitive")
}

private func insertionAppCategories() {
    check(AppLists.category(bundleID: "com.openai.chat", url: nil) == .ai && AppLists.category(bundleID: "com.anthropic.claudefordesktop", url: nil) == .ai,
          "native AI chat apps")
    check(AppLists.category(bundleID: "com.apple.Safari", url: "https://claude.ai/new") == .ai, "AI chat site")
    check(AppLists.category(bundleID: "com.google.Chrome", url: "https://www.perplexity.ai/search") == .ai, "subdomain of an AI chat site")
    check(AppLists.category(bundleID: "com.google.Chrome", url: "https://notclaude.ai/") == .other, "host suffixes match whole labels")
    check(AppLists.category(bundleID: "com.google.Chrome", url: "https://mail.google.com/mail/u/0/") == .email, "Core's hosts still apply")
    check(AppLists.category(bundleID: "com.tinyspeck.slackmacgap", url: nil) == .work && AppLists.category(bundleID: "com.unknown", url: nil) == .other,
          "Core's apps still apply")
    check(AppLists.category(bundleID: "com.openai.chat", url: "https://chatgpt.com") == .ai, "a URL on a non-browser is ignored")
}

private func insertionFnKeyboard() {
    check(FnKeyboard.hasFnKey([.init(vendorID: 0x046D, isBuiltIn: true)]), "built-in keyboards have Fn")
    check(FnKeyboard.hasFnKey([.init(vendorID: 0x046D, isBuiltIn: false), .init(vendorID: 0x004C, isBuiltIn: false)]), "a Bluetooth Apple keyboard")
    check(!FnKeyboard.hasFnKey([.init(vendorID: 0x046D, isBuiltIn: false)]) && !FnKeyboard.hasFnKey([]), "third-party only, or none")
}

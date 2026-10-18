import AppKit
import Carbon.HIToolbox
import SwiftUI
import SuperFlowCore

/// Rules for changing a shortcut (behaviour.md §3.2). Public for the self-test.
public enum ShortcutEditing {
    public enum Outcome: Equatable {
        /// The new map, and the action that lost the chord when it was taken from another one.
        case assigned(ShortcutMap, replaced: ShortcutAction?)
        case rejected(String)
    }

    /// The actions Settings lists, in order (Command Mode only while it is turned on).
    public static func editableActions(commandMode: Bool) -> [ShortcutAction] {
        [.pushToTalk, .handsFree] + (commandMode ? [.commandMode] : []) + [.pasteLastText, .copyLastText, .dismiss, .notetaker]
    }

    static let functionKeys: Set<UInt16> = Set([kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11,
                                                kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20].map(UInt16.init))
    static let shiftKeys: Set<UInt16> = [UInt16(kVK_Shift), UInt16(kVK_RightShift)]

    /// Makes `chord` the action's only shortcut, taking it from another action if needed.
    public static func assign(_ chord: KeyChord, to action: ShortcutAction, in map: ShortcutMap) -> Outcome {
        guard !chord.keys.isEmpty else { return .rejected("Press a key or a combination.") }
        guard chord.keys.count <= ShortcutMap.maxKeys else { return .rejected("Use at most \(ShortcutMap.maxKeys) keys.") }
        let modifiers = chord.keys.filter { KeyChord.modifierCodes.contains($0) || KeyChord.isMouse($0) }
        let plain = chord.keys.subtracting(modifiers)
        let standalone = plain.allSatisfy { functionKeys.contains($0) } || (action == .dismiss && plain == [UInt16(kVK_Escape)])
        // A letter alone, or with only Shift, would get in the way of typing.
        if !plain.isEmpty && !standalone && (modifiers.isEmpty || modifiers.isSubset(of: shiftKeys)) {
            return .rejected("Add ⌃, ⌥, ⌘ or Fn so the shortcut doesn't get in the way of typing.")
        }
        var updated = map
        let previous = updated.bindings[chord]
        updated.bindings = updated.bindings.filter { $0.value != action }
        updated.bindings[chord] = action
        return .assigned(updated, replaced: previous == action ? nil : previous)
    }

    /// Restores every default shortcut for the keyboard in use.
    public static func defaults(hasFnKey: Bool) -> ShortcutMap { hasFnKey ? .macDefaults : .noFnKeyboardDefaults }

    /// Turns the keys held during a recording into a chord: the modifier keycodes held plus the key pressed.
    public static func chord(held: Set<UInt16>, key: UInt16?) -> KeyChord? {
        var keys = held
        if let key { keys.insert(key) }
        return keys.isEmpty ? nil : KeyChord(keys)
    }
}

extension ShortcutAction {
    var detail: String {
        switch self {
        case .pushToTalk: "Hold to dictate. Let go to insert."
        case .handsFree: "Press to start, press again to finish."
        case .commandMode: "Hold with text selected and say how to change it."
        case .pasteLastText: "Pastes your last dictation again."
        case .copyLastText: "Copies your last dictation."
        case .dismiss: "Cancels the dictation in progress."
        case .notetaker: "Starts notes for the meeting you're in."
        default: ""
        }
    }
}

/// Records one chord for an action: through the hotkey service when its tap runs, else from the hub's own key events.
@MainActor
final class ShortcutRecorder: ObservableObject {
    static let shared = ShortcutRecorder()

    @Published private(set) var recording: ShortcutAction?
    @Published private(set) var held: Set<UInt16> = []
    private var monitor: Any?
    private var peak: Set<UInt16> = []
    private var listening = false
    var onMessage: (String, Bool) -> Void = { _, _ in }

    func start(_ action: ShortcutAction) {
        cancel()
        recording = action
        listenToHotkeys()
        Services.hotkeys?.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Services.hotkeys?.isRecording = false
        recording = nil
        held = []
        peak = []
    }

    /// One long-lived consumer: an AsyncStream ends for good when its consuming task is cancelled.
    private func listenToHotkeys() {
        guard !listening, let hotkeys = Services.hotkeys else { return }
        listening = true
        Task { @MainActor [weak self] in
            for await chord in hotkeys.recorderEvents {
                guard let self, self.recording != nil else { continue }
                self.finish(chord)
            }
        }
    }

    /// Returns true when the event was used.
    private func handle(_ event: NSEvent) -> Bool {
        guard recording != nil else { return false }
        if event.type == .keyDown {
            finish(ShortcutEditing.chord(held: held, key: event.keyCode))
            return true
        }
        let code = event.keyCode
        guard KeyChord.modifierCodes.contains(code) else { return true }
        if held.contains(code) { held.remove(code) } else { held.insert(code) }
        peak.formUnion(held)
        // Modifiers only (Fn, Fn + Control…): the chord is what was held at the peak, taken when all are released.
        if held.isEmpty, !peak.isEmpty { finish(KeyChord(peak)) }
        return true
    }

    private func finish(_ chord: KeyChord?) {
        guard let action = recording, let chord else { return }
        cancel()
        switch ShortcutEditing.assign(chord, to: action, in: Defaults[.shortcuts]) {
        case .assigned(let map, let replaced):
            Defaults[.shortcuts] = map
            Services.hotkeys?.update(map)
            onMessage(replaced.map { "\(chord.displayString) moved here from \($0.title)." } ?? "\(action.title): \(chord.displayString)", false)
        case .rejected(let reason):
            onMessage(reason, true)
        }
    }
}

struct ShortcutsCard: View {
    @EnvironmentObject private var state: HubState
    @ObservedObject private var recorder = ShortcutRecorder.shared
    @Default(.shortcuts) private var shortcuts
    @Default(.commandModeEnabled) private var commandMode

    var body: some View {
        HubCard(spacing: 12) {
            ForEach(ShortcutEditing.editableActions(commandMode: commandMode), id: \.self) { action in
                SettingsRow(title: action.title, detail: action.detail, controlWidth: 260) {
                    if recorder.recording == action {
                        Text(recorder.held.isEmpty ? "Press the new shortcut…" : KeyChord(recorder.held).displayString + " …")
                            .hubText(.sm, .emphasis, HubColor.dawnStrong)
                        Button("Cancel") { recorder.cancel() }.buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
                    } else {
                        let chords = shortcuts.chords(for: action)
                        if chords.isEmpty { Text("Not set").hubText(.sm, .regular, HubColor.tertiary) }
                        ForEach(chords, id: \.self) { ChordView(chord: $0) }
                        Button("Change") { recorder.start(action) }.buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
                    }
                }
                Rule()
            }
            SwitchRow(title: "Double-tap Fn for hands-free", detail: "Tap Fn twice to start, once more to finish.",
                      isOn: Binding(get: { shortcuts.doubleTapFnForHandsFree }, set: { on in
                          var map = shortcuts
                          map.doubleTapFnForHandsFree = on
                          shortcuts = map
                          Services.hotkeys?.update(map)
                      }))
        }
        HStack {
            Spacer()
            Button("Reset to defaults") {
                let map = ShortcutEditing.defaults(hasFnKey: Services.hotkeys?.hasFnKey ?? true)
                shortcuts = map
                Services.hotkeys?.update(map)
                state.showToast("Shortcuts reset")
            }
            .buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
        }
        .padding(.horizontal, 4)
        .onAppear { recorder.onMessage = { [weak state] in state?.showToast($0, isError: $1) } }
        .onDisappear { recorder.cancel() }
    }
}

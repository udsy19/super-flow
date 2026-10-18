import AppKit
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum InsertionKitModule {
    @MainActor public static func install() {
        Services.insertion = TextInserter.shared
        Services.context = ContextReader.shared
        Services.hotkeys = HotkeyMonitor.shared
    }
}

/// Placeholder inserter (behaviour.md §9): copies to the clipboard and reports it, so nothing is lost before the
/// paste-and-restore and AX paths exist.
@MainActor
final class TextInserter: TextInserting {
    static let shared = TextInserter()

    func insert(_ text: String, actions: [PostInsertAction], method: InsertionMethod) async -> InsertionOutcome {
        copyToClipboard(text)
        return .leftOnClipboard(reason: "Insertion isn't available yet")
    }

    func selectedText() async -> String? { nil }

    func replaceSelection(with text: String) async -> InsertionOutcome {
        copyToClipboard(text)
        return .leftOnClipboard(reason: "Insertion isn't available yet")
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func observeEdits(of insertedText: String, window: TimeInterval) async -> String? { nil }
}

/// Placeholder context reader (behaviour.md §6): the frontmost app and its category, no AX text yet.
@MainActor
final class ContextReader: AppContextReading {
    static let shared = ContextReader()

    var frontmostApp: AppRecord? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        return AppRecord(bundleID: bundleID, name: app.localizedName ?? bundleID, category: AppLists.category(bundleID: bundleID))
    }

    func snapshot() -> AppContext { AppContext(app: frontmostApp) }
}

/// Placeholder hotkey monitor (behaviour.md §3): holds the shortcut map and the event streams; the CGEventTap and
/// chord matcher come next. `start()` succeeds without installing anything so launch never fails.
@MainActor
final class HotkeyMonitor: HotkeyMonitoring {
    static let shared = HotkeyMonitor()
    private var map = Defaults[.shortcuts]
    private var eventContinuation: AsyncStream<HotkeyEvent>.Continuation?
    private var recorderContinuation: AsyncStream<KeyChord>.Continuation?
    private(set) lazy var events: AsyncStream<HotkeyEvent> = AsyncStream { self.eventContinuation = $0 }
    private(set) lazy var recorderEvents: AsyncStream<KeyChord> = AsyncStream { self.recorderContinuation = $0 }
    private(set) var isRunning = false
    var isRecording = false
    var hasFnKey: Bool { true }

    func start() throws { isRunning = true }
    func stop() { isRunning = false }
    func update(_ map: ShortcutMap) { self.map = map }
}

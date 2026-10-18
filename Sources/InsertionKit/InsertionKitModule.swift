import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch): insertion at the cursor, the app context
/// reader and the hotkey event tap (behaviour.md §3, §6, §9).
public enum InsertionKitModule {
    @MainActor public static func install() {
        Services.insertion = TextInserter.shared
        Services.context = ContextReader.shared
        Services.hotkeys = HotkeyMonitor.shared
    }
}

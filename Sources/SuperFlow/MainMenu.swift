import AppKit
import SuperFlowCore

/// The app menu bar when the hub is focused (behaviour.md §16.2): Super Flow, File, Edit, Dictation, Window, Help.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()

        let app = NSMenu(title: "Super Flow")
        app.addItem(withTitle: "About Super Flow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(Target.showSettings), keyEquivalent: ",").target = Target.shared
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Super Flow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Super Flow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(submenu(app))

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(submenu(file))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(submenu(edit))

        let dictation = NSMenu(title: "Dictation")
        dictation.addItem(withTitle: "Start Dictation", action: #selector(Target.startDictation), keyEquivalent: "").target = Target.shared
        dictation.addItem(withTitle: "Paste Last Transcript", action: #selector(Target.pasteLast), keyEquivalent: "").target = Target.shared
        dictation.addItem(withTitle: "Copy Last Transcript", action: #selector(Target.copyLast), keyEquivalent: "").target = Target.shared
        menu.addItem(submenu(dictation))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(submenu(window))
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Super Flow Help", action: #selector(Target.openHelp), keyEquivalent: "?").target = Target.shared
        help.addItem(withTitle: "Report an Issue", action: #selector(Target.reportIssue), keyEquivalent: "").target = Target.shared
        menu.addItem(submenu(help))
        NSApp.helpMenu = help
        return menu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @MainActor final class Target: NSObject {
        static let shared = Target()
        @objc func showSettings() { Services.hub.showSettings(.general) }
        @objc func startDictation() { Services.dictation.start(mode: .handsFree, source: .keyboard) }
        @objc func pasteLast() { Services.dictation.pasteLastTranscript() }
        @objc func copyLast() { Services.dictation.copyLastTranscript() }
        @objc func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/udsy19/super-flow#readme")!) }
        @objc func reportIssue() { NSWorkspace.shared.open(URL(string: "https://github.com/udsy19/super-flow/issues")!) }
    }
}

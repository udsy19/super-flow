import AppKit
import ApplicationServices
import SuperFlowCore

/// AppContextReading (behaviour.md §6): the frontmost app with its page URL and window title, its category, and the
/// focused field. The field's role always decides `isEditable` and `isSecure` (a password field is never read and
/// never dictated into); its text is read only with context awareness on (`useAxContext`).
@MainActor
final class ContextReader: AppContextReading {
    static let shared = ContextReader()

    var frontmostApp: AppRecord? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        var url: String?
        var windowTitle: String?
        if AXIsProcessTrusted() {
            let element = AX.application(app.processIdentifier)
            let window = AX.element(element, kAXFocusedWindowAttribute)
            windowTitle = window.flatMap { AX.string($0, kAXTitleAttribute) }.flatMap { $0.isEmpty ? nil : $0 }
            if AppLists.browsers.contains(bundleID) { url = Self.pageURL(app: element, window: window) }
        }
        return AppRecord(bundleID: bundleID, name: app.localizedName ?? bundleID, url: url, windowTitle: windowTitle,
                         category: AppLists.category(bundleID: bundleID, url: url))
    }

    func snapshot() -> AppContext {
        let app = frontmostApp
        guard let field = FocusedField.current() else {
            return AppContext(app: app, isSecure: SecureInput.isHeldByFrontmostApp)
        }
        var context = AppContext(app: app, isEditable: field.isEditable, isSecure: field.isSecure, fieldRole: field.role)
        guard Defaults[.useAxContext], !field.isSecure, let value = field.value else { return context }
        let window = TextWindow(value: value, selection: field.selectedRange, limit: AppContext.maxTextboxLength)
        context.textBefore = window.before
        context.selectedText = window.selected
        context.textAfter = window.after
        return context
    }

    /// The page in a browser: the URL of the web area holding the focus, else the window's document.
    private static func pageURL(app: AXUIElement, window: AXUIElement?) -> String? {
        func web(_ url: URL?) -> String? { ["http", "https"].contains(url?.scheme?.lowercased()) ? url?.absoluteString : nil }
        var element = AX.element(app, kAXFocusedUIElementAttribute)
        for _ in 0..<40 {
            guard let current = element else { break }
            if AX.string(current, kAXRoleAttribute) == "AXWebArea", let url = web(AX.attribute(current, kAXURLAttribute) as? URL) { return url }
            element = AX.element(current, kAXParentAttribute)
        }
        return window.flatMap { AX.string($0, kAXDocumentAttribute) }.flatMap { web(URL(string: $0)) }
    }
}

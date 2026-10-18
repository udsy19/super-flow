import AppKit
import ApplicationServices
import SuperFlowCore

/// App categories (behaviour.md §6.2): Core's tables plus the AI chat apps and sites, which `AppLists` leaves to
/// this module.
public enum AppClassifier {
    /// Native AI chat apps and AI editors not already in `AppLists.ai`.
    public static let aiChatApps: Set<String> = [
        "com.openai.chat", "com.anthropic.claudefordesktop", "ai.perplexity.mac", "ai.elementlabs.lmstudio",
        "jan.ai.app", "co.podzim.BoltGPT", "dev.zed.Zed",
    ]
    /// AI chat sites in a browser, matched like `AppLists.hostCategories` (the host or any subdomain).
    public static let aiChatHosts: [String] = [
        "chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "aistudio.google.com", "perplexity.ai",
        "copilot.microsoft.com", "chat.deepseek.com", "grok.com", "chat.mistral.ai", "poe.com", "meta.ai",
        "v0.dev", "v0.app", "bolt.new", "lovable.dev",
    ]

    public static func category(bundleID: String, url: String?) -> AppCategory {
        if AppLists.browsers.contains(bundleID), let host = url.flatMap({ URL(string: $0)?.host?.lowercased() }),
           aiChatHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .ai }
        if aiChatApps.contains(bundleID) { return .ai }
        return AppLists.category(bundleID: bundleID, url: url)
    }
}

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
                         category: AppClassifier.category(bundleID: bundleID, url: url))
    }

    func snapshot() -> AppContext {
        let app = frontmostApp
        guard let field = FocusedField.current() else {
            return AppContext(app: app, isSecure: SecureInput.isHeldByFrontmostApp)
        }
        var context = AppContext(app: app, isEditable: field.isEditable, isSecure: field.isSecure)
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

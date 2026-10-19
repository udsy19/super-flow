import Foundation

/// The app-type tables (behaviour.md §6.2) shipped as data: bundle ids, URL hosts and the conferencing apps the
/// meeting detector watches (§20.3). InsertionKit classifies with `category(bundleID:url:)`.
public enum AppLists {
    public static let personalMessaging: Set<String> = [
        "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "com.texts.app", "com.facebook.archon", "com.beeper.desktop",
        "ru.keepcoder.Telegram", "org.telegram.desktop", "org.whispersystems.signal-desktop", "com.hnc.Discord", "com.tencent.xinWeChat",
    ]
    public static let workMessaging: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.microsoft.teams", "com.microsoft.teams2", "us.zoom.xos", "com.google.Chat", "com.intercom.Intercom",
    ]
    public static let email: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.superhuman.electron", "com.mimestream.Mimestream", "com.readdle.smartemail-Mac",
        "org.mozilla.thunderbird", "com.hey.app", "com.frontapp.Front",
    ]
    public static let document: Set<String> = [
        "notion.id", "com.microsoft.Word", "com.apple.iWork.Pages", "md.obsidian", "net.shinyfrog.bear", "com.apple.Notes",
        "com.linear", "com.figma.Desktop", "com.apple.dt.Xcode", "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.WebStorm",
        "com.sublimetext.4", "com.apple.TextEdit", "com.craft.craft", "com.apple.freeform",
    ]
    /// AI coding editors and terminals, plus the native AI chat apps of behaviour.md §6.2.
    public static let ai: Set<String> = [
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.microsoft.VSCode", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "com.openai.chat", "com.anthropic.claudefordesktop", "ai.perplexity.mac", "ai.elementlabs.lmstudio", "jan.ai.app",
        "co.podzim.BoltGPT", "dev.zed.Zed",
    ]
    /// AI chat sites in a browser, matched like `hostCategories` (the host or any subdomain).
    public static let aiChatHosts: [String] = [
        "chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "aistudio.google.com", "perplexity.ai",
        "copilot.microsoft.com", "chat.deepseek.com", "grok.com", "chat.mistral.ai", "poe.com", "meta.ai",
        "v0.dev", "v0.app", "bolt.new", "lovable.dev",
    ]
    public static let terminal: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "org.alacritty", "co.zeit.hyper",
    ]
    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen", "com.openai.atlas",
        "ai.perplexity.comet", "company.thebrowser.dia",
    ]

    /// URL host → category for pages in a browser.
    public static let hostCategories: [(suffix: String, category: AppCategory)] = [
        ("web.whatsapp.com", .personalMessaging), ("messenger.com", .personalMessaging), ("web.telegram.org", .personalMessaging),
        ("discord.com", .personalMessaging), ("x.com", .personalMessaging), ("twitter.com", .personalMessaging), ("reddit.com", .personalMessaging),
        ("slack.com", .work), ("teams.microsoft.com", .work), ("linkedin.com", .work), ("chat.google.com", .work),
        ("mail.google.com", .email), ("outlook.live.com", .email), ("outlook.office.com", .email), ("mail.superhuman.com", .email),
        ("mail.proton.me", .email), ("app.hey.com", .email),
        ("docs.google.com", .document), ("notion.so", .document), ("linear.app", .document), ("figma.com", .document),
    ]

    public static func category(bundleID: String, url: String? = nil) -> AppCategory {
        if browsers.contains(bundleID), let url, let host = URL(string: url)?.host?.lowercased() {
            if aiChatHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .ai }
            if let match = hostCategories.first(where: { host == $0.suffix || host.hasSuffix("." + $0.suffix) }) { return match.category }
            return .other
        }
        if personalMessaging.contains(bundleID) { return .personalMessaging }
        if workMessaging.contains(bundleID) { return .work }
        if email.contains(bundleID) { return .email }
        if terminal.contains(bundleID) { return .terminal }
        if ai.contains(bundleID) { return .ai }
        if document.contains(bundleID) { return .document }
        return .other
    }

    // MARK: Meetings (§20.3)

    /// Native conferencing apps: bundle id → platform.
    public static let conferencingApps: [String: MeetingPlatform] = [
        "us.zoom.xos": .zoom, "com.microsoft.teams": .teams, "com.microsoft.teams2": .teams, "com.tinyspeck.slackmacgap": .slack,
        "com.cisco.webexmeetingsapp": .webex, "com.webex.meetingmanager": .webex, "com.hnc.Discord": .discord,
        "net.whatsapp.WhatsApp": .whatsapp, "com.apple.FaceTime": .facetime,
    ]

    /// Browser meeting hosts: host suffix → platform.
    public static let meetingHosts: [(suffix: String, platform: MeetingPlatform)] = [
        ("meet.google.com", .googleMeet), ("teams.microsoft.com", .teams), ("teams.live.com", .teams), ("zoom.us", .zoom),
        ("whereby.com", .other), ("webex.com", .webex),
    ]

    /// Recognises a conference link in a calendar event's URL, location or notes (§20.10).
    public static func platform(forJoinURL url: URL) -> MeetingPlatform? {
        guard let host = url.host?.lowercased() else { return nil }
        return meetingHosts.first { host == $0.suffix || host.hasSuffix("." + $0.suffix) }?.platform
    }
}

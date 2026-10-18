import AppKit
import SwiftUI
import SuperFlowCore

/// Style per app category and the auto-cleanup level (behaviour.md §8.2, §8.4).
enum StyleTab: Hashable { case category(StyleCategory), cleanup }

struct StylePage: View {
    @EnvironmentObject private var state: HubState

    var body: some View {
        PageScaffold(title: "Style", subtitle: "How Super Flow writes in different kinds of apps.") {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 28) {
                UnderlineTabs(tabs: tabs, selection: $state.styleTab)
                switch state.styleTab {
                case .category(let category): CategoryStyle(category: category)
                case .cleanup: CleanupLevelPicker()
                }
            }
        }
    }

    private var tabs: [(value: StyleTab, title: String)] {
        StyleCategory.allCases.map { (StyleTab.category($0), $0.title) } + [(StyleTab.cleanup, "Auto cleanup")]
    }
}

extension StyleCategory {
    var title: String {
        switch self {
        case .personal: "Personal messages"
        case .work: "Work messages"
        case .email: "Email"
        case .other: "Other"
        }
    }

    var scope: String {
        switch self {
        case .personal: "Used in personal messengers."
        case .work: "Used in workplace chat."
        case .email: "Used in email apps."
        case .other: "Used in every other app: documents, notes, AI chats, code editors."
        }
    }

    /// Bundle ids of the apps the category covers (behaviour.md §6.2).
    var bundleIDs: [String] {
        switch self {
        case .personal: AppLists.personalMessaging.sorted()
        case .work: AppLists.workMessaging.sorted()
        case .email: AppLists.email.sorted()
        case .other: (AppLists.document.union(AppLists.ai)).sorted()
        }
    }
}

extension WritingStyle {
    var title: String {
        switch self {
        case .formal: "Formal."
        case .casual: "Casual"
        case .veryCasual: "very casual"
        case .excited: "Excited!"
        }
    }

    var rule: String {
        switch self {
        case .formal: "Caps + Punctuation"
        case .casual: "Caps + Less punctuation"
        case .veryCasual: "No Caps + Less punctuation"
        case .excited: "More exclamations"
        }
    }

    func sample(for category: StyleCategory) -> String {
        switch (category, self) {
        case (.personal, .formal): "Hey, are you free for lunch tomorrow? Noon works for me."
        case (.personal, .casual): "Hey are you free for lunch tomorrow? Noon works for me"
        case (.personal, _): "hey are you free for lunch tomorrow? noon works for me"
        case (.work, .formal): "Hi, if you have a minute today, let's go over the launch numbers."
        case (.work, .casual): "Hi if you have a minute today let's go over the launch numbers"
        case (.work, _): "Hi, if you have a minute today, let's go over the launch numbers!"
        case (.email, .formal): "Hi Sam,\n\nThanks for the call today. I'll send the draft by Friday.\n\nBest,\nAlex"
        case (.email, .casual): "Hi Sam, thanks for the call today. I'll send the draft by Friday\n\nBest,\nAlex"
        case (.email, _): "Hi Sam,\n\nThanks for the call today! I'll send the draft by Friday.\n\nBest,\nAlex"
        case (.other, .formal): "So far, the new routine is working well. Tomorrow, I'll try the longer version."
        case (.other, .casual): "So far the new routine is working well. Tomorrow I'll try the longer version"
        case (.other, _): "So far, the new routine is working really well! Tomorrow, I'll try the longer version."
        }
    }
}

struct CategoryStyle: View {
    let category: StyleCategory
    @Default(.styleProfile) private var profile

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text(category.scope).hubText(.sm, .regular, HubColor.tertiary)
                Spacer()
                InstalledApps(bundleIDs: category.bundleIDs)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(WritingStyle.options(for: category), id: \.self) { style in
                    StyleCard(style: style, category: category, selected: profile.style(for: category) == style) {
                        var changed = profile
                        changed.styles[category] = style
                        profile = changed
                    }
                }
            }
        }
    }
}

/// Icons of the installed apps in a category (at most eight), each with its name as a tooltip.
struct InstalledApps: View {
    let bundleIDs: [String]

    var body: some View {
        let apps = bundleIDs.compactMap { id -> (name: String, icon: NSImage)? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                    NSWorkspace.shared.icon(forFile: url.path))
        }
        HStack(spacing: 2) {
            ForEach(Array(apps.prefix(8).enumerated()), id: \.offset) { _, app in
                Image(nsImage: app.icon).resizable().frame(width: 22, height: 22).help(app.name)
            }
        }
    }
}

struct StyleCard: View {
    let style: WritingStyle
    let category: StyleCategory
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.title).hubDisplay(28)
                        Text(style.rule).hubText(.sm, .regular, HubColor.tertiary)
                    }
                    Spacer()
                    ZStack {
                        Circle().strokeBorder(selected ? HubColor.primary : HubColor.neutral500.opacity(0.35), lineWidth: 1.5)
                        if selected { Circle().fill(HubColor.primary).padding(4) }
                    }
                    .frame(width: 18, height: 18)
                }
                Text(style.sample(for: category))
                    .hubText(.sm)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HubColor.card))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous)
                .fill(hovering && !selected ? HubColor.hover.opacity(0.6) : HubColor.backgroundTertiary))
            .overlay(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous)
                .strokeBorder(selected ? HubColor.primary : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension CleanupLevel {
    var title: String {
        switch self {
        case .none: "None"
        case .light: "Light"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var summary: String {
        switch self {
        case .none: "Transcribes exactly what you said, mistakes included"
        case .light: "Cleans up filler words and grammar"
        case .medium: "Edits for clarity and conciseness"
        case .high: "Rewrites for brevity and polish"
        }
    }

    var example: String {
        switch self {
        case .none: "so um I think we should uh move the review to thursday no wait friday"
        case .light: "I think we should move the review to Friday."
        case .medium: "Let's move the review to Friday."
        case .high: "Can we move the review to Friday?"
        }
    }
}

struct CleanupLevelPicker: View {
    @Default(.styleProfile) private var profile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Applies to every dictation, in every app. Your original words are always kept: in History, choose Undo AI edit to go back to them.")
                .hubText(.sm, .regular, HubColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(CleanupLevel.allCases, id: \.self) { level in
                    CleanupOption(level: level, selected: profile.cleanupLevel == level) {
                        var changed = profile
                        changed.cleanupLevel = level
                        profile = changed
                    }
                }
            }
        }
    }
}

struct CleanupOption: View {
    let level: CleanupLevel
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().strokeBorder(selected ? HubColor.primary : HubColor.neutral500.opacity(0.35), lineWidth: 1.5)
                    if selected { Circle().fill(HubColor.primary).padding(4) }
                }
                .frame(width: 18, height: 18)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(level.title).hubText(.sm, .strong)
                        if level == .light { Chip(text: "Default") }
                    }
                    Text(level.summary).hubText(.sm, .regular, HubColor.tertiary)
                }
                .frame(width: 330, alignment: .leading)
                Text(level.example)
                    .hubText(.sm, .regular, level == .none ? HubColor.tertiary : HubColor.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HubColor.card))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: SFMetrics.Radius.lg, style: .continuous)
                .fill(hovering && !selected ? HubColor.hover.opacity(0.6) : HubColor.backgroundTertiary))
            .overlay(RoundedRectangle(cornerRadius: SFMetrics.Radius.lg, style: .continuous)
                .strokeBorder(selected ? HubColor.primary : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

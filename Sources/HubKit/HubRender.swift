import AppKit
import SwiftUI
import SuperFlowCore

/// Offscreen renders of the hub's screens for design review and the self-test. The window is never ordered on
/// screen; the view tree is drawn with `cacheDisplay`.
public enum HubRender {
    public enum Screen: String, CaseIterable, Sendable {
        case home, history, dictionary, snippets, style, styleCleanup, notes, meetings, meetingSummary, meetingTranscript
        case settingsGeneral, settingsSystem, settingsMeetings, settingsModels, settingsPrivacy, settingsVibeCoding
        case settingsExperimental, settingsAbout, wordEditor
        case onboardingWelcome, onboardingPrivacy, onboardingPermissions, onboardingTryIt
    }

    /// Renders one screen with whatever `Services` currently holds. `dark` forces the dark appearance (onboarding
    /// always draws light).
    @MainActor public static func image(_ screen: Screen, dark: Bool = false, notes: NotesStore? = nil,
                                        size: NSSize = SFMetrics.Hub.defaultSize) -> NSBitmapImageRep? {
        _ = NSApplication.shared
        let state = HubState()
        let store = HubStore(notes: notes)
        configure(state, store: store, for: screen)
        let permissions = PermissionCenter.shared
        if screen == .onboardingPermissions {
            permissions.fixed = [.microphone: .granted, .accessibility: .granted, .inputMonitoring: .notDetermined,
                                 .systemAudio: .notDetermined, .calendar: .denied]
        }
        defer { permissions.fixed = nil; permissions.refresh() }
        permissions.refresh()

        let window = HubWindow.make(rootView: HubRootView(state: state, store: store), size: size)
        window.appearance = state.mode == .onboarding ? NSAppearance(named: .aqua) : NSAppearance(named: dark ? .darkAqua : .aqua)
        return capture(window, includingFrame: true)
    }

    /// One Settings pane at its full height (the modal scrolls), for reviewing every row.
    @MainActor public static func settingsPage(_ pane: SettingsPane, dark: Bool = false) -> NSBitmapImageRep? {
        _ = NSApplication.shared
        let state = HubState()
        let store = HubStore()
        let page = SettingsPaneView(pane: pane)
            .padding(48)
            .frame(width: SFMetrics.Settings.size.width - SFMetrics.Settings.sidebarWidth - SFMetrics.Settings.sidebarPadding * 2,
                   alignment: .leading)
            .background(HubColor.sheet)
            .environmentObject(state)
            .environmentObject(store)
            .environmentObject(store.notes)
        let host = NSHostingView(rootView: page)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return capture(window, includingFrame: false)
    }

    @MainActor private static func capture(_ window: NSWindow, includingFrame: Bool) -> NSBitmapImageRep? {
        defer { window.contentView = nil; window.close() }
        guard let content = window.contentView else { return nil }
        let view = includingFrame ? (content.superview ?? content) : content
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    @MainActor private static func configure(_ state: HubState, store: HubStore, for screen: Screen) {
        switch screen {
        case .home: state.go(.home)
        case .history: state.go(.history)
        case .dictionary: state.go(.dictionary)
        case .snippets: state.go(.snippets)
        case .style: state.go(.style)
        case .styleCleanup:
            state.go(.style)
            state.styleTab = .cleanup
        case .notes: state.go(.notes)
        case .meetings: state.go(.meetings)
        case .meetingSummary, .meetingTranscript:
            if let id = store.meetings.first(where: { $0.summary != nil })?.id ?? store.meetings.first?.id {
                state.openMeeting(id, tab: screen == .meetingSummary ? .summary : .transcript)
            } else {
                state.go(.meetings)
            }
        case .settingsGeneral: state.settingsPane = .general
        case .settingsSystem: state.settingsPane = .system
        case .settingsMeetings: state.settingsPane = .notetaker
        case .settingsModels: state.settingsPane = .models
        case .settingsPrivacy: state.settingsPane = .dataAndPrivacy
        case .settingsVibeCoding: state.settingsPane = .vibeCoding
        case .settingsExperimental: state.settingsPane = .experimental
        case .settingsAbout: state.settingsPane = .about
        case .wordEditor:
            state.go(.dictionary)
            state.modal = .word(store.dictionary.first { $0.replacement != nil })
        case .onboardingWelcome, .onboardingPrivacy, .onboardingPermissions, .onboardingTryIt:
            state.mode = .onboarding
            state.onboardingStep = switch screen {
            case .onboardingWelcome: .welcome
            case .onboardingPrivacy: .privacy
            case .onboardingPermissions: .permissions
            default: .tryIt
            }
        }
    }
}

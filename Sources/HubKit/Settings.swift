import AppKit
import ServiceManagement
import SwiftUI
import SuperFlowCore

// Settings, a modal over the hub (behaviour.md §13, ui-reference.md §4).

extension SettingsPane {
    var title: String {
        switch self {
        case .general: "General"
        case .system: "System"
        case .notetaker: "Meetings"
        case .models: "Models"
        case .vibeCoding: "Vibe coding"
        case .experimental: "Experimental"
        case .dataAndPrivacy: "Privacy"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .system: "macwindow"
        case .notetaker: "record.circle"
        case .models: "cpu"
        case .vibeCoding: "chevron.left.forwardslash.chevron.right"
        case .experimental: "flask"
        case .dataAndPrivacy: "lock"
        case .about: "info.circle"
        }
    }

    /// Sidebar order: everyday panes first.
    static let ordered: [SettingsPane] = [.general, .system, .notetaker, .models, .dataAndPrivacy, .vibeCoding, .experimental, .about]
}

struct SettingsModal: View {
    @EnvironmentObject private var state: HubState
    let pane: SettingsPane

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                SettingsSidebar(selection: pane)
                ScrollView {
                    SettingsPaneView(pane: pane)
                        .padding(48)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(pane)
            }
            .frame(width: min(SFMetrics.Settings.size.width, geo.size.width - 48),
                   height: min(SFMetrics.Settings.size.height, geo.size.height - 48))
            .background(RoundedRectangle(cornerRadius: SFMetrics.Settings.radius, style: .continuous).fill(HubColor.sheet))
            .clipShape(RoundedRectangle(cornerRadius: SFMetrics.Settings.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SFMetrics.Settings.radius, style: .continuous).strokeBorder(HubColor.border))
            .overlay(alignment: .topTrailing) {
                IconButton(symbol: "xmark", help: "Close settings") { state.settingsPane = nil }
                    .keyboardShortcut(.cancelAction)
                    .padding(14)
            }
            .shadow(color: .black.opacity(0.14), radius: 25, y: 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SettingsSidebar: View {
    @EnvironmentObject private var state: HubState
    let selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings").sectionLabelStyle(HubColor.neutral500.opacity(0.8)).padding(8)
            ForEach(SettingsPane.ordered, id: \.self) { pane in
                SettingsNavItem(pane: pane, active: pane == selection) { state.settingsPane = pane }
            }
            Spacer()
            Text("Super Flow \(AppInfo.version)").hubText(.xs, .regular, HubColor.tertiary).padding(.horizontal, 8).padding(.vertical, 6)
        }
        .padding(SFMetrics.Settings.sidebarPadding)
        .frame(width: SFMetrics.Settings.sidebarWidth + SFMetrics.Settings.sidebarPadding * 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HubColor.backgroundTertiary)
        .overlay(alignment: .trailing) { Rectangle().fill(HubColor.border).frame(width: 1) }
    }
}

struct SettingsNavItem: View {
    let pane: SettingsPane
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: pane.symbol).font(.system(size: 14)).frame(width: 20, height: 20)
                Text(pane.title).hubText(.sm, .emphasis)
            }
            .foregroundStyle(HubColor.foreground)
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: SFMetrics.Settings.itemMinHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SFMetrics.Settings.itemRadius, style: .continuous)
                .fill(active || hovering ? HubColor.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Page header and sections (§4.2): serif 28 title, gap 36 between sections, section title 15/20 600.
struct SettingsPage<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).hubDisplay(28)
                Text(description).hubText(.sm, .regular, HubColor.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).hubText(.sm, .strong)
            content
        }
    }
}

/// A card of rows separated by rules.
struct RowsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HubCard(spacing: 12) { content }
    }
}

/// A switch row bound to a Bool setting, with an optional side effect.
struct SwitchRow: View {
    let title: String
    var detail: String?
    let isOn: Binding<Bool>

    var body: some View {
        SettingsRow(title: title, detail: detail) { Toggle("", isOn: isOn).hubSwitch() }
    }
}

/// A switch row bound to a Bool setting; redraws when the setting changes anywhere. `inverted` shows a "hide…" key as
/// "show…"; `apply` runs the side effect of a change.
struct SettingSwitch: View {
    let title: String
    var detail: String?
    let inverted: Bool
    let apply: (Bool) -> Void
    @Default private var value: Bool

    init(_ title: String, detail: String? = nil, _ key: Defaults.Key<Bool>, inverted: Bool = false, then apply: @escaping (Bool) -> Void = { _ in }) {
        self.title = title; self.detail = detail; self.inverted = inverted; self.apply = apply
        _value = Default(key)
    }

    var body: some View {
        SwitchRow(title: title, detail: detail, isOn: Binding(get: { inverted ? !value : value }, set: { on in
            value = inverted ? !on : on
            apply(on)
        }))
    }
}

struct SettingsPaneView: View {
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .general: GeneralPane()
        case .system: SystemPane()
        case .notetaker: MeetingsPane()
        case .models: ModelsPane()
        case .vibeCoding: VibeCodingPane()
        case .experimental: ExperimentalPane()
        case .dataAndPrivacy: PrivacyPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - General (§13.1)

struct GeneralPane: View {
    @Default(.overrideAudioDeviceId) private var device

    var body: some View {
        SettingsPage(title: "General", description: "Your shortcuts, microphone and the languages you speak.") {
            SettingsSection(title: "Shortcuts") { ShortcutsCard() }
            SettingsSection(title: "Microphone") {
                RowsCard {
                    SettingsRow(title: "Microphone", detail: "Used for dictation. Automatic prefers the built-in mic.", controlWidth: 220) {
                        MenuPicker(options: [("", "Automatic")] + (Services.audio?.devices ?? []).map { ($0.id, $0.name) },
                                   selection: Binding(get: { device ?? "" }, set: { device = $0.isEmpty ? nil : $0 }), width: 220)
                    }
                }
            }
            SettingsSection(title: "Languages") { LanguagesCard() }
        }
    }
}

/// Every language an engine knows (`SupportedLanguages`) plus anything already selected, by display name.
enum LanguageList {
    static var all: [String] {
        let codes = Set(SupportedLanguages.all).union(Defaults[.selectedLanguages])
        return codes.sorted { HubFormat.languageName($0) < HubFormat.languageName($1) }
    }
}

struct LanguagesCard: View {
    @EnvironmentObject private var state: HubState
    @Default(.selectedLanguages) private var selected
    @Default(.autoDetectLanguage) private var autoDetect
    @State private var expanded = false

    var body: some View {
        RowsCard {
            SettingsRow(title: "Languages you speak", detail: summary, controlWidth: 100) {
                Button(expanded ? "Done" : "Change") { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
                    .buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
            }
            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 10) {
                    ForEach(LanguageList.all, id: \.self) { code in
                        HStack(spacing: 8) {
                            CheckBox(checked: selected.contains(code)) { toggle(code) }
                            Text(HubFormat.languageName(code)).hubText(.sm)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Rule()
            SwitchRow(title: "Detect the language automatically", detail: "Best when you switch between languages a lot.",
                      isOn: Binding(get: { autoDetect }, set: { on in
                          if !on && selected.isEmpty { state.showToast("Pick at least one language first.", isError: true); return }
                          autoDetect = on
                      }))
        }
    }

    private var summary: String {
        let names = selected.map(HubFormat.languageName)
        return names.isEmpty ? "Detected automatically" : names.joined(separator: ", ")
    }

    private func toggle(_ code: String) {
        if selected.contains(code) {
            guard selected.count > 1 || autoDetect else { state.showToast("Keep at least one language, or turn on automatic detection.", isError: true); return }
            selected.removeAll { $0 == code }
        } else {
            selected.append(code)
        }
    }
}

// MARK: - System (§13.2)

struct SystemPane: View {
    @EnvironmentObject private var state: HubState
    @Default(.theme) private var theme
    @Default(.lastUpdateCheck) private var lastCheck

    var body: some View {
        SettingsPage(title: "System", description: "How Super Flow fits into your Mac.") {
            SettingsSection(title: "App") {
                RowsCard {
                    SettingSwitch("Open at login", detail: "Starts quietly when you log in, so dictation is always ready.",
                              .openAtLogin, then: LoginItem.apply)
                    Rule()
                    SettingSwitch("Show in the Dock", .hideAppInDock, inverted: true, then: { show in
                        NSApp.setActivationPolicy(show ? .regular : .accessory)
                    })
                    Rule()
                    SettingSwitch("Show the Flow Bar at all times", detail: "When off, the bar appears only while you dictate.",
                              .hideFlowBarPermanently, inverted: true, then: { show in Services.flowBar?.setRestingVisible(show) })
                    Rule()
                    SettingsRow(title: "Appearance") {
                        MenuPicker(options: [(AppTheme.light, "Light"), (.dark, "Dark"), (.system, "Match the system")], selection: $theme)
                    }
                }
            }
            SettingsSection(title: "Sound") {
                RowsCard {
                    SettingSwitch("Dictation and notification sounds", detail: "A soft click when dictation starts and stops.",
                              .enableSounds)
                    Rule()
                    SettingSwitch("Mute other audio while dictating", detail: "Turns down music and videos while you talk.",
                              .shouldMuteAudio)
                }
            }
            SettingsSection(title: "Dictionary") {
                RowsCard {
                    SettingSwitch("Learn from my corrections", detail: "Adds a word to your dictionary when you fix it right after dictating.",
                              .shouldAutoLearnWords)
                }
            }
            SettingsSection(title: "Updates") {
                RowsCard {
                    SettingSwitch("Install updates automatically", detail: updateDetail, .installUpdates)
                }
            }
            SettingsSection(title: "Tutorial") {
                RowsCard {
                    SettingsRow(title: "Restart the tutorial", detail: "Walk through permissions and the practice step again.") {
                        Button("Restart") { state.settingsPane = nil; Services.onboarding?.restartTutorial() }
                            .buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
                    }
                }
            }
        }
    }

    private var updateDetail: String {
        let checked = lastCheck > 0
            ? "Last checked \(HubFormat.dayTitle(Date(timeIntervalSince1970: lastCheck)).lowercased()) at \(HubFormat.time(Date(timeIntervalSince1970: lastCheck)))."
            : "Not checked yet."
        return "Checks GitHub for new versions and installs them while you're idle. \(checked)"
    }
}

/// Open at login (SMAppService), mirrored in `Defaults[.openAtLogin]`.
@MainActor
enum LoginItem {
    static func apply(_ on: Bool) {
        do {
            if on, SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !on, SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch {
            Log.hub.error("Open at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Meetings (§13.6, owner decision: a detected meeting always asks)

struct MeetingsPane: View {
    @Default(.meetingDetection) private var detection
    @Default(.meetingReminderLead) private var reminder
    @Default(.notetakerMaxRecordingLength) private var maxLength
    @ObservedObject private var permissions = PermissionCenter.shared

    var body: some View {
        SettingsPage(title: "Meetings", description: "Super Flow notices calls and asks before taking notes. It never records on its own.") {
            SettingsSection(title: "When a call starts") {
                RowsCard {
                    SettingsRow(title: "Meeting detection", detail: "Asks above the Flow Bar whether to take notes.") {
                        MenuPicker(options: [(MeetingDetectionPolicy.notify, "Ask me"), (.doNothing, "Off")],
                                   selection: Binding(get: { detection }, set: { policy in
                                       detection = policy
                                       if policy == .notify { Services.meetingDetector?.start() } else { Services.meetingDetector?.stop() }
                                   }))
                    }
                    Rule()
                    SettingSwitch("Stop when the call ends", detail: "Notes finish on their own when the meeting app hangs up.",
                              .notetakerAutoEndEnabled)
                    Rule()
                    SettingsRow(title: "Remind me before calendar meetings") {
                        MenuPicker(options: [(MeetingReminderLead.never, "Never"), (.rightBefore, "Right before"), (.oneMinute, "1 minute before"),
                                             (.twoMinutes, "2 minutes before")], selection: $reminder)
                    }
                }
            }
            SettingsSection(title: "While recording") {
                RowsCard {
                    SettingSwitch("Open my notes when recording starts", .notetakerOpenWindowOnRecord)
                    Rule()
                    SettingSwitch("Show the live transcript", .notetakerLiveTranscriptEnabled)
                    Rule()
                    SettingSwitch("Label speakers", detail: "Shows who said what in the transcript.", .notetakerAttributeNamesEnabled)
                    Rule()
                    SettingSwitch("Hide from screen sharing", detail: "Keeps the Flow Bar and your notes out of shared screens and recordings.",
                              .hideMeetingRecorderInScreenShare)
                    Rule()
                    SettingsRow(title: "Maximum length", detail: "Recording stops here, with a warning shortly before.") {
                        MenuPicker(options: SettingsOptions.maxRecordingLengths.map { ($0, Self.lengthLabel($0)) },
                                   selection: $maxLength)
                    }
                }
            }
            SettingsSection(title: "Calendar") {
                RowsCard {
                    SettingsRow(title: "Calendar access", detail: "Meeting titles, attendees and reminders come from the calendars on this Mac. Read-only.") {
                        PermissionControl(kind: .calendar, center: permissions)
                    }
                }
            }
            SettingsSection(title: "Apps Super Flow watches for calls") {
                HubCard {
                    FlowLayout(spacing: 8) {
                        ForEach(DetectedApps.native, id: \.self) { Chip(text: $0, symbol: "video") }
                    }
                    Text("Also in any browser: \(DetectedApps.web.joined(separator: ", ")).").hubText(.xs, .regular, HubColor.tertiary)
                }
            }
        }
        .onAppear { permissions.watch() }
        .onDisappear { permissions.unwatch() }
    }
}

extension MeetingsPane {
    /// "30 minutes", "1 hour", "2 hours".
    static func lengthLabel(_ seconds: Int) -> String {
        seconds < 3600 ? "\(seconds / 60) minutes" : (seconds == 3600 ? "1 hour" : "\(seconds / 3600) hours")
    }
}

enum DetectedApps {
    static var native: [String] {
        Array(Set(AppLists.conferencingApps.values.map(HubFormat.platformName))).sorted()
    }

    static var web: [String] {
        var seen: Set<String> = []
        return AppLists.meetingHosts.map { $0.platform == .other ? $0.suffix.components(separatedBy: ".").first!.capitalized : HubFormat.platformName($0.platform) }
            .filter { seen.insert($0).inserted }
    }
}

/// "Allowed", "Allow" or "Open Settings" for one permission.
struct PermissionControl: View {
    let kind: PermissionKind
    @ObservedObject var center: PermissionCenter

    var body: some View {
        switch center.status(kind) {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                .hubText(.sm, .emphasis, HubColor.success)
        case .unavailable:
            Text("Not available on this Mac").hubText(.xs, .regular, HubColor.tertiary)
        case .denied:
            Button("Open Settings") { center.request(kind) }.buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
        case .notDetermined:
            Button("Allow") { center.request(kind) }.buttonStyle(HubButtonStyle(variant: .primary, size: .xs))
        }
    }
}

/// Wraps children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Models (local-models.md §5; owner decision: automatic downloads, status only)

struct ModelsPane: View {
    @EnvironmentObject private var store: HubStore
    @Default(.autoDownloadModels) private var auto
    @Default(.asrModelID) private var speechModel
    @Default(.cleanupModelID) private var cleanupModel
    @Default(.selectedLanguages) private var languages
    @Default(.autoDetectLanguage) private var autoDetect

    var body: some View {
        let _ = store.modelRevision
        let preset = ModelCatalog.preset(isAppleSilicon: Machine.isAppleSilicon, memoryBytes: Machine.memoryBytes)
        let mine = ModelSummary.queue.filter { $0.kind != .vad }
        let others = ModelCatalog.all.filter { m in m.kind != .vad && !m.isBuiltIn && !mine.contains { $0.id == m.id } }
        let engines = ModelCatalog.dictationEngines(isAppleSilicon: Machine.isAppleSilicon,
                                                    hasAppleSpeech: Services.models?.state(of: ModelCatalog.appleSpeech.id) == .installed)
        let cleanupModels = ModelCatalog.cleanupModels(isAppleSilicon: Machine.isAppleSilicon, memoryBytes: Machine.memoryBytes)
        SettingsPage(title: "Models", description: "Speech, cleanup and meeting notes run on these models, on this Mac. They download on their own.") {
            RowsCard {
                SwitchRow(title: "Download models automatically",
                          detail: Services.models.map { HubFormat.autoDownloadText($0.autoDownloadStatus) { ModelCatalog.descriptor($0)?.name ?? $0 } },
                          isOn: Binding(get: { auto }, set: { on in
                              auto = on
                              Services.models?.startAutomaticDownloads()
                          }))
                if !engines.isEmpty {
                    Rule()
                    SettingsRow(title: "Dictation engine", detail: HubFormat.engineDetail(speechModel, englishOnlyUser: englishOnly), controlWidth: 290) {
                        MenuPicker(options: engines.map { ($0.id, HubFormat.engineChoice($0)) },
                                   selection: Binding(get: { engines.contains { $0.id == speechModel } ? speechModel : ModelCatalog.parakeetV3.id },
                                                      set: { speechModel = $0 }), width: 290)
                    }
                }
                if !cleanupModels.isEmpty {
                    Rule()
                    SettingsRow(title: "Cleanup model",
                                detail: "Fixes punctuation, fillers and self-corrections. The 4B model is more accurate and takes about twice as long.",
                                controlWidth: 290) {
                        MenuPicker(options: cleanupModels.map { ($0.id, HubFormat.cleanupChoice($0)) },
                                   selection: Binding(get: { cleanupModel ?? ModelCatalog.qwen35_2B.id }, set: { cleanupModel = $0 }), width: 290)
                    }
                }
            }
            SettingsSection(title: "For this Mac · \(preset.name)") {
                RowsCard {
                    ForEach(mine) { model in
                        ModelRow(model: model, status: Services.models?.state(of: model.id) ?? .notDownloaded)
                        if model.id != mine.last?.id { Rule() }
                    }
                }
            }
            if !others.isEmpty {
                SettingsSection(title: "Other models") {
                    RowsCard {
                        ForEach(others) { model in
                            ModelRow(model: model, status: Services.models?.state(of: model.id) ?? .notDownloaded)
                            if model.id != others.last?.id { Rule() }
                        }
                    }
                }
            }
            HStack {
                Text("Using \(HubFormat.bytes(Services.models?.diskUsage ?? 0)) on disk.").hubText(.xs, .regular, HubColor.tertiary)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([SuperFlowPaths.models]) }
                    .buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
            }
        }
    }
}

extension ModelsPane {
    /// Whether every dictation language is English (Nemotron covers only English).
    private var englishOnly: Bool {
        !autoDetect && !languages.isEmpty && languages.allSatisfy { SupportedLanguages.base($0) == "en" }
    }
}

/// One model; `status` comes from the parent so the row redraws as progress arrives.
struct ModelRow: View {
    @EnvironmentObject private var state: HubState
    let model: ModelDescriptor
    let status: ModelState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).hubText(.sm, .emphasis)
                    Text("\(HubFormat.modelPurpose(model)) · \(HubFormat.bytes(model.bytes)) · \(model.licence)")
                        .hubText(.xs, .regular, HubColor.tertiary)
                }
                Spacer()
                controls(status)
            }
            if case .downloading(let fraction) = status { progress(fraction) }
            if case .paused(let fraction) = status { progress(fraction) }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func progress(_ fraction: Double) -> some View {
        HStack(spacing: 10) {
            ProgressLine(fraction: fraction)
            Text(ModelSummary.percent(fraction)).hubText(.xs, .regular, HubColor.tertiary).monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder private func controls(_ status: ModelState) -> some View {
        switch status {
        case .installed:
            Label("Downloaded", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).hubText(.xs, .emphasis, HubColor.success)
            Button("Remove") { remove() }.buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
        case .downloading:
            Button("Pause") { Services.models?.pause(model.id) }.buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
        case .paused:
            Text("Paused").hubText(.xs, .regular, HubColor.tertiary)
            Button("Resume") { download() }.buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
        case .notDownloaded:
            Button("Download") { download() }.buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
        case .damaged:
            Text("Damaged").hubText(.xs, .emphasis, HubColor.destructive)
            Button("Download again") { download() }.buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
        }
    }

    private func download() {
        guard let models = Services.models else { return }
        let name = model.name
        Task { @MainActor in
            do { for try await _ in models.download(model.id) {} } catch ModelError.cancelled {
            } catch { state.showToast("\(name): \(error.localizedDescription)", isError: true) }
        }
    }

    private func remove() {
        let message = Defaults[.autoDownloadModels] && ModelSummary.queue.contains { $0.id == model.id }
            ? "It frees \(HubFormat.bytes(model.bytes)). Super Flow downloads it again while automatic downloads are on."
            : "It frees \(HubFormat.bytes(model.bytes)). You can download it again any time."
        state.confirm("Remove \(model.name)?", message, confirmTitle: "Remove") {
            do { try Services.models?.delete(model.id) } catch { state.showToast("Couldn't remove \(model.name).", isError: true) }
        }
    }
}

// MARK: - Privacy (§13.5, §20.9)

struct PrivacyPane: View {
    @EnvironmentObject private var state: HubState
    @Default(.localDataPolicy) private var policy
    @Default(.meetingAudioRetentionDays) private var audioDays
    @Default(.meetingTranscriptRetentionDays) private var transcriptDays

    var body: some View {
        SettingsPage(title: "Privacy", description: "Everything Super Flow hears and writes stays on this Mac.") {
            HubCard(spacing: 18) {
                PrivacyFact(symbol: "internaldrive", title: "Your audio, transcripts and notes",
                            detail: "Saved in your Library on this Mac. Never uploaded.")
                PrivacyFact(symbol: "cpu", title: "Local models",
                            detail: "Speech recognition, cleanup and meeting summaries run on this Mac, with no cloud service.")
                PrivacyFact(symbol: "network", title: "Two kinds of network use",
                            detail: "Model downloads from Hugging Face and update checks with GitHub. Nothing you say is sent.")
                PrivacyFact(symbol: "eye.slash", title: "No telemetry", detail: "No analytics, crash reports or tracking. There's no account.")
            }
            SettingsSection(title: "Context") {
                RowsCard {
                    SettingSwitch("Context awareness",
                              detail: "Reads a little text around the cursor to spell names right and continue your sentence.",
                              .useAxContext)
                }
            }
            SettingsSection(title: "What to keep") {
                RowsCard {
                    SettingsRow(title: "Dictation history", detail: "Transcripts on the History page. Dictation audio is kept 14 days.",
                                controlWidth: 200) {
                        MenuPicker(options: [(LocalDataPolicy.store, "Keep"), (.autoDelete24h, "Delete after 24 hours"), (.never, "Don't save")],
                                   selection: $policy, width: 200)
                    }
                    Rule()
                    SettingsRow(title: "Meeting audio", detail: "Deleted after this. Transcripts and notes stay.", controlWidth: 200) {
                        MenuPicker(options: SettingsOptions.meetingAudioRetentionDays.map { ($0, Self.retention($0)) }, selection: $audioDays, width: 200)
                    }
                    Rule()
                    SettingsRow(title: "Meeting transcripts and notes", detail: "Whole meetings are deleted after this.", controlWidth: 200) {
                        MenuPicker(options: SettingsOptions.transcriptRetentionDays.map { ($0, Self.retention($0)) }, selection: $transcriptDays,
                                   width: 200)
                    }
                }
            }
            SettingsSection(title: "Delete") {
                RowsCard {
                    SettingsRow(title: "Delete all dictation history", detail: "Removes every transcript and its audio from this Mac.") {
                        Button("Delete…") { eraseHistory() }.buttonStyle(HubButtonStyle(variant: .destructive, size: .xs))
                    }
                }
            }
        }
    }

    static func retention(_ days: Int) -> String {
        days <= RetentionPolicy.keepForever ? "Keep forever" : "Keep \(RetentionPolicy.label(days: days))"
    }

    private func eraseHistory() {
        state.confirm("Delete all dictation history?", "Every transcript and its audio will be removed from this Mac. This can't be undone.",
                      confirmTitle: "Delete everything") {
            do {
                let n = try Services.history?.eraseDictations() ?? 0
                state.showToast(n == 1 ? "Deleted 1 dictation" : "Deleted \(HubFormat.count(n)) dictations")
            } catch {
                state.showToast("Couldn't delete the history.", isError: true)
            }
        }
    }
}

struct PrivacyFact: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(HubColor.neutral600).frame(width: 22, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).hubText(.sm, .emphasis)
                Text(detail).hubText(.sm, .regular, HubColor.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Vibe coding, Experimental (§13.3, §13.4)

struct VibeCodingPane: View {
    var body: some View {
        SettingsPage(title: "Vibe coding", description: "Dictation tuned for code editors and AI coding tools.") {
            RowsCard {
                SettingSwitch("File tagging in chat", detail: "In Cursor and Windsurf, a file name you say becomes an @-mention.",
                          .ideFileTagging)
                Rule()
                SettingSwitch("Variable recognition", detail: "Writes names like getUserName the way they appear in your editor.",
                          .cursorIdeIntegration)
            }
        }
    }
}

struct ExperimentalPane: View {
    var body: some View {
        SettingsPage(title: "Experimental", description: "Features that are still settling in. Turn them on to try them.") {
            RowsCard {
                SettingSwitch("Command Mode", detail: "Select text, hold Fn + Control and say how to change it.", .commandModeEnabled)
                Rule()
                SettingSwitch("Press Enter command", detail: "End a dictation with “press enter” to send it.",
                          .pressEnterCommandEnabled)
                Rule()
                SettingSwitch("Style detection", detail: "Matches the style of what's already in the text field.",
                          .styleDetectionEnabled)
                Rule()
                SettingSwitch("Pause media while dictating", detail: "Pauses music and videos instead of muting them.",
                          .shouldPauseAudio)
                Rule()
                SettingSwitch("Stacked messages", detail: "Splits a long dictation into separate messages in chat apps.",
                          .stackedMessagesEnabled)
            }
        }
    }
}

// MARK: - About

/// The bundle's icon; outside an app bundle (development, renders) the same mark drawn in SwiftUI.
struct AppIcon: View {
    var body: some View {
        if Bundle.main.bundleURL.pathExtension == "app", let icon = NSApp.applicationIconImage {
            Image(nsImage: icon).resizable()
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.937)], startPoint: .top, endPoint: .bottom))
                .overlay(BrandMark(height: 34, color: Color(white: 0.08)))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .padding(6)
        }
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { $0 == short ? short : "\(short) (\($0))" } ?? short
    }
    static let repository = URL(string: "https://github.com/udsy19/super-flow")!
    static let privacy = URL(string: "https://github.com/udsy19/super-flow/blob/main/PRIVACY.md")!
    static let issues = URL(string: "https://github.com/udsy19/super-flow/issues")!
    /// System Settings › Privacy & Security, where "Open Anyway" lives.
    static let securitySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?General")!
}

struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HStack(spacing: 18) {
                AppIcon().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Super Flow").hubDisplay(28)
                    Text("Version \(AppInfo.version)").hubText(.sm, .regular, HubColor.tertiary)
                    HStack(spacing: 8) {
                        Link("Source code", destination: AppInfo.repository)
                        Text("·").foregroundStyle(HubColor.tertiary)
                        Link("Privacy", destination: AppInfo.privacy)
                        Text("·").foregroundStyle(HubColor.tertiary)
                        Link("Report an issue", destination: AppInfo.issues)
                    }
                    .hubText(.sm, .emphasis)
                    .tint(HubColor.foreground)
                }
            }
            Text("Voice dictation and meeting notes that run entirely on your Mac.").hubText(.md)
            HubCard(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield").font(.system(size: 15)).foregroundStyle(HubColor.neutral600)
                    Text("Signed, not notarized").hubText(.sm, .emphasis)
                }
                Text("Super Flow isn't notarized by Apple. If macOS says it can't check the app, open System Settings › Privacy & Security and click Open Anyway. You only do this once.")
                    .hubText(.sm, .regular, HubColor.tertiary).fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy & Security") { NSWorkspace.shared.open(AppInfo.securitySettings) }
                    .buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
            }
            SettingsSection(title: "Open models") {
                HubCard(spacing: 12) {
                    ForEach(ModelCatalog.all.filter { !$0.attribution.isEmpty && !$0.isBuiltIn }) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name).hubText(.sm, .emphasis)
                            Text(model.attribution).hubText(.xs, .regular, HubColor.tertiary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

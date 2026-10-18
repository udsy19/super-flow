import AppKit
import SwiftUI
import SuperFlowCore

/// Everything inside the hub window: the hub or onboarding, then modals, Settings and the toast on top.
struct HubRootView: View {
    @ObservedObject var state: HubState
    @ObservedObject var store: HubStore

    var body: some View {
        ZStack {
            switch state.mode {
            case .hub: HubShell()
            case .onboarding: OnboardingView()
            }
            if state.mode == .hub, let pane = state.settingsPane {
                ModalBackdrop { state.settingsPane = nil }
                SettingsModal(pane: pane).transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            if let modal = state.modal {
                ModalBackdrop { state.modal = nil }
                ModalCard(modal: modal).transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            ToastLayer()
        }
        .animation(.spring(response: 0.18, dampingFraction: 1), value: state.settingsPane)
        .animation(.spring(response: 0.18, dampingFraction: 1), value: state.modal?.id)
        .environmentObject(state)
        .environmentObject(store)
        .environmentObject(store.notes)
    }
}

// MARK: - Shell (§3.2)

struct HubShell: View {
    @EnvironmentObject private var state: HubState

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Sidebar()
                .frame(width: SFMetrics.Hub.sidebarWidth)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HubColor.background)
                // Corners painted over rather than clipped: a clip becomes a mask layer, which offscreen renders drop.
                .overlay(PageCorners().fill(HubColor.backgroundTertiary, style: FillStyle(eoFill: true)).allowsHitTesting(false))
                .overlay(PageShape().stroke(HubColor.border, lineWidth: 1).allowsHitTesting(false))
                .padding(.top, SFMetrics.Hub.headerHeight)
                .padding(.trailing, SFMetrics.Hub.pageMargin.right)
                .padding(.bottom, SFMetrics.Hub.pageMargin.bottom)
        }
        .background(HubColor.backgroundTertiary)
        .ignoresSafeArea()
    }

    @ViewBuilder private var page: some View {
        switch state.section {
        case .home: HomePage()
        case .history: HistoryPage()
        case .dictionary: DictionaryPage()
        case .snippets: SnippetsPage()
        case .style: StylePage()
        case .notes: NotesPage()
        case .meetings:
            if let id = state.meetingID { MeetingDetailPage(meetingID: id) } else { MeetingsPage() }
        }
    }
}

/// The page card: radius 24 at the top, 16 at the bottom (§3.2).
struct PageShape: Shape {
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: SFMetrics.Hub.pageCornerRadii.top, bottomLeadingRadius: SFMetrics.Hub.pageCornerRadii.bottom,
                               bottomTrailingRadius: SFMetrics.Hub.pageCornerRadii.bottom, topTrailingRadius: SFMetrics.Hub.pageCornerRadii.top,
                               style: .continuous).path(in: rect)
    }
}

/// A scrolling page: padding 40 40 0, content max 1046 wide, title row 24/32 600 with 24 below (§3.2).
struct PageScaffold<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: title, subtitle: subtitle) { accessory }
                    .padding(.bottom, SFMetrics.Hub.titleBottomMargin)
                VStack(alignment: .leading, spacing: SFMetrics.Hub.contentGap) { content }
            }
            .frame(maxWidth: SFMetrics.Hub.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, SFMetrics.Hub.pagePadding.left)
            .padding(.top, SFMetrics.Hub.pagePadding.top)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

struct PageTitle<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).hubHeading(3)
                if let subtitle { Text(subtitle).hubText(.sm, .regular, HubColor.tertiary) }
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { accessory }
        }
    }
}

/// The window background outside the page card's rounded corners.
struct PageCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(PageShape().path(in: rect))
        return path
    }
}

// MARK: - Sidebar (§3.2)

struct Sidebar: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore

    var body: some View {
        VStack(alignment: .leading, spacing: SFMetrics.Hub.navItemGap) {
            HStack(spacing: 9) {
                BrandMark(height: 17)
                Text("Super Flow").font(.system(size: 17, weight: .semibold)).tracking(-0.2).foregroundStyle(HubColor.foreground)
            }
            .frame(height: 25)
            .padding(.horizontal, 9)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)

            ForEach(HubSection.allCases, id: \.self) { section in
                NavItem(title: section.title, symbol: section.symbol, active: state.section == section) { state.go(section) }
            }
            Spacer(minLength: 16)
            ModelStatusBadge()
            Rule().padding(.vertical, 6)
            NavItem(title: "Settings", symbol: "gearshape", active: state.settingsPane != nil) { state.settingsPane = .general }
        }
        .padding(.horizontal, SFMetrics.Hub.sidebarPadding)
        .padding(.top, SFMetrics.Hub.headerHeight)
        .padding(.bottom, SFMetrics.Hub.sidebarPadding)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct NavItem: View {
    let title: String
    let symbol: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: SFMetrics.Hub.navIconSize, height: SFMetrics.Hub.navIconSize)
                Text(title).hubText(.sm, .emphasis)
            }
            .foregroundStyle(HubColor.foreground)
            .padding(SFMetrics.Hub.navItemPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SFMetrics.Hub.navItemRadius, style: .continuous)
                .fill(active || hovering ? HubColor.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// While models download (or wait), a quiet status at the bottom of the sidebar; it opens Settings › Models.
struct ModelStatusBadge: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore

    var body: some View {
        let _ = store.modelRevision
        if let summary = ModelSummary.current(), !summary.isComplete {
            Button { state.settingsPane = .models } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 12, weight: .medium))
                        Text(summary.headline).hubText(.xs, .emphasis)
                    }
                    .foregroundStyle(HubColor.foreground)
                    if let fraction = summary.fraction { ProgressLine(fraction: fraction, height: 3) }
                    Text(summary.detail).hubText(.xs, .regular, HubColor.tertiary).lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HubColor.background))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HubColor.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Settings › Models")
        }
    }
}

// MARK: - Modals, toast

struct ModalBackdrop: View {
    let dismiss: () -> Void
    var body: some View {
        Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: dismiss).transition(.opacity)
    }
}

/// The modal card (§3.3): background, 1 pt border, radius 12, shadow xl.
struct ModalChrome<Content: View>: View {
    var width: CGFloat = 440
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) { content }
            .padding(28)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SFMetrics.Controls.modalRadius, style: .continuous).fill(HubColor.background))
            .overlay(RoundedRectangle(cornerRadius: SFMetrics.Controls.modalRadius, style: .continuous).strokeBorder(HubColor.border))
            .shadow(color: .black.opacity(0.12), radius: 25, y: 20)
    }
}

struct ModalCard: View {
    @EnvironmentObject private var state: HubState
    let modal: HubModal

    var body: some View {
        switch modal {
        case .word(let entry): WordEditor(entry: entry)
        case .snippet(let snippet): SnippetEditor(snippet: snippet)
        case .confirm(let confirmation):
            ModalChrome(width: 400) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(confirmation.title).hubHeading(5)
                    Text(confirmation.message).hubText(.sm, .regular, HubColor.tertiary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { state.modal = nil }.buttonStyle(HubButtonStyle(variant: .ghost)).keyboardShortcut(.cancelAction)
                    Button(confirmation.confirmTitle) {
                        state.modal = nil
                        confirmation.action()
                    }
                    .buttonStyle(HubButtonStyle(variant: .destructive))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

/// Bottom-right toast (§3.3): 300 wide, padding 8 12, radius 6, dark fill.
struct ToastLayer: View {
    @EnvironmentObject private var state: HubState

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let toast = state.toast {
                    HStack(spacing: 8) {
                        Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(toast.isError ? Color(nsColor: SFColor.destructive500) : Color(nsColor: SFColor.green400))
                        Text(toast.message).hubText(.sm, .regular, .white).lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: SFMetrics.Hub.toastWidth)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HubColor.toastFill))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HubColor.toastBorder))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
                }
            }
        }
        .padding(16)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.toast)
        .allowsHitTesting(false)
    }
}

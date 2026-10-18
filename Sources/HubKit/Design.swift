import AppKit
import SwiftUI
import SuperFlowCore

// The hub's SwiftUI building blocks, drawn with the Core tokens (ui-reference.md §1, §3.3, §4.2). Values that the
// reference names but Core does not carry (neutral steps, dawn-700) are defined here, light and dark.

// MARK: - Colours

enum HubColor {
    static let background = Color(nsColor: SFColor.background)
    static let backgroundSecondary = Color(nsColor: SFColor.backgroundSecondary)
    static let backgroundTertiary = Color(nsColor: SFColor.backgroundTertiary)
    static let card = Color(nsColor: SFColor.card)
    static let primary = Color(nsColor: SFColor.primary)
    static let primaryForeground = Color(nsColor: SFColor.primaryForeground)
    static let foreground = Color(nsColor: SFColor.foreground)
    static let tertiary = Color(nsColor: SFColor.foregroundTertiary)
    static let border = Color(nsColor: SFColor.border)
    static let destructive = Color(nsColor: SFColor.destructive)
    static let success = Color(nsColor: SFColor.success)
    static let recording = Color(nsColor: SFColor.recording)
    /// `--neutral-500`: sand-950 light, foreground-tertiary dark (§1.2).
    static let neutral500 = Color(nsColor: SFColor.dynamic("hub.neutral500", light: SFColor.sand950, dark: SFColor.vast400))
    /// `--neutral-600`: vast-900 light, foreground-secondary dark.
    static let neutral600 = Color(nsColor: SFColor.dynamic("hub.neutral600", light: SFColor.vast900, dark: SFColor.vast100))
    /// Hover and selection fill of nav items and rows (`--neutral-200`).
    static let hover = Color(nsColor: SFColor.dynamic("hub.hover", light: SFColor.sand600, dark: SFColor.vast900))
    static let ghostHover = Color(nsColor: SFColor.dynamic("hub.ghostHover", light: NSColor(hex: "#c5c0b333"),
                                                           dark: NSColor.white.withAlphaComponent(0.08)))
    static let switchOff = Color(nsColor: SFColor.dynamic("hub.switchOff", light: SFColor.vast300, dark: SFColor.vast700))
    /// `--shade-white`: the Settings modal fill (white light, background dark).
    static let sheet = Color(nsColor: SFColor.dynamic("hub.sheet", light: .white, dark: SFColor.vast950))
    /// `--dawn-700` #a26ec1: onboarding progress, accent words, done checkboxes.
    static let dawnStrong = Color(nsColor: NSColor(hex: "#a26ec1"))
    static let dawnTint = Color(nsColor: SFColor.dynamic("hub.dawnTint", light: NSColor(hex: "#faf1ff"), dark: NSColor(hex: "#3c2947")))
    static let toastFill = Color(nsColor: SFColor.vast950)
    static let toastBorder = Color(nsColor: SFColor.vast900)
    static let keyFill = Color(nsColor: SFColor.dynamic("hub.keyFill", light: .white, dark: SFColor.vast800))
    static let keyEdge = Color(nsColor: SFColor.dynamic("hub.keyEdge", light: NSColor(hex: "#d3ced6"), dark: SFColor.vast925))
    static let keyBorder = Color(nsColor: SFColor.dynamic("hub.keyBorder", light: SFColor.sand600, dark: SFColor.vast700))
    static let keyInk = Color(nsColor: SFColor.dynamic("hub.keyInk", light: SFColor.vast900, dark: SFColor.vast50))

    /// Speaker label colours, by speaker ordinal (ui-reference.md §10.1).
    static let speakers: [Color] = ["#E89F4D", "#6B3FAB", "#3F9970", "#3D5FE0", "#C0392B", "#1ABC9C", "#D68A2D", "#8E44AD",
                                    "#2980B9", "#27AE60", "#E67E22", "#16A085", "#9B59B6", "#34495E", "#D35400"]
        .map { Color(nsColor: NSColor(hex: $0)) }
}

// MARK: - Type

enum HubWeight {
    case regular, emphasis, strong, bold
    var ns: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .emphasis: SFFont.emphasisWeight
        case .strong: .semibold
        case .bold: .bold
        }
    }
}

extension View {
    /// Text at one of the reference sizes (§1.3) with its line height.
    func hubText(_ size: SFFont.TextSize = .sm, _ weight: HubWeight = .regular, _ color: Color = HubColor.foreground) -> some View {
        let font = SFFont.text(size, weight: weight.ns)
        return self.font(Font(font)).foregroundStyle(color).lineSpacing(HubType.extraLeading(font, SFFont.size(size).lineHeight))
    }

    /// Serif display text (§1.3): tracking −0.04 em.
    func hubDisplay(_ size: CGFloat, _ color: Color = HubColor.foreground) -> some View {
        font(Font(HubType.serif(size))).tracking(-0.04 * size).foregroundStyle(color)
    }

    func hubHeading(_ level: Int, _ color: Color = HubColor.foreground) -> some View {
        font(Font(SFFont.heading(level))).foregroundStyle(color)
    }

    /// 12/20 600 uppercase, tracking .075 em (§1.3 section labels).
    func sectionLabelStyle(_ color: Color = HubColor.tertiary) -> some View {
        font(Font(SFFont.sectionLabel)).tracking(SFFont.sectionLabelTracking).textCase(.uppercase).foregroundStyle(color)
    }
}

enum HubType {
    static func extraLeading(_ font: NSFont, _ lineHeight: CGFloat) -> CGFloat {
        max(0, lineHeight - (font.ascender - font.descender + font.leading))
    }

    static func serif(_ size: CGFloat, italic: Bool = false) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }
}

// MARK: - Buttons (§3.3)

struct HubButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, outline, ghost, destructive }
    enum Size { case xs, sm, md, lg }
    var variant: Variant = .secondary
    var size: Size = .sm
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        HubButtonBody(configuration: configuration, style: self)
    }
}

private struct HubButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let style: HubButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(Font(font))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .frame(maxWidth: style.fullWidth ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: SFMetrics.Controls.buttonRadius, style: .continuous).fill(fill))
            .overlay {
                if style.variant == .outline {
                    RoundedRectangle(cornerRadius: SFMetrics.Controls.buttonRadius, style: .continuous).strokeBorder(HubColor.border)
                }
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .onHover { hovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var font: NSFont {
        let weight = style.variant == .secondary ? NSFont.Weight.semibold : SFFont.emphasisWeight
        return style.size == .xs ? SFFont.text(.xs, weight: weight) : SFFont.text(.sm, weight: weight)
    }
    private var height: CGFloat {
        switch style.size {
        case .xs: 28
        case .sm: 32
        case .md: 36
        case .lg: 44
        }
    }
    private var horizontalPadding: CGFloat {
        switch style.size {
        case .xs: 10
        case .sm: 12
        case .md: 16
        case .lg: 24
        }
    }
    private var foreground: Color {
        switch style.variant {
        case .primary: HubColor.primaryForeground
        case .destructive: .white
        case .secondary, .outline, .ghost: HubColor.foreground
        }
    }
    private var fill: Color {
        switch style.variant {
        case .primary: hovering ? HubColor.primary.opacity(0.88) : HubColor.primary
        case .secondary: hovering ? HubColor.hover.opacity(0.7) : HubColor.backgroundSecondary
        case .outline: hovering ? HubColor.backgroundTertiary : HubColor.background
        case .ghost: hovering ? HubColor.ghostHover : .clear
        case .destructive: Color(nsColor: hovering ? NSColor(hex: "#f87171") : SFColor.destructive500)
        }
    }
}

/// A square icon button (§3.3 IconButton `toolbar`): 28 × 28, radius 6, tertiary icon, hover fill.
struct IconButton: View {
    let symbol: String
    var help: String
    var size: CGFloat = 28
    var tint: Color = HubColor.neutral600
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size > 28 ? 8 : 6, style: .continuous)
                    .fill(hovering ? HubColor.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

// MARK: - Switch (§3.3): 42 × 25, thumb 21, travel 17

struct HubSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? HubColor.primary : HubColor.switchOff)
                Circle().fill(configuration.isOn ? HubColor.background : Color.white)
                    .frame(width: SFMetrics.Controls.switchThumb, height: SFMetrics.Controls.switchThumb)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: SFMetrics.Controls.switchSize.width, height: SFMetrics.Controls.switchSize.height)
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.2, dampingFraction: 1)) { configuration.isOn.toggle() }
            }
            .accessibilityAddTraits(.isButton)
        }
    }
}

extension Toggle {
    func hubSwitch() -> some View { toggleStyle(HubSwitchStyle()).labelsHidden() }
}

// MARK: - Text input (§3.3): 36 tall, radius 8, white, 1 pt border, 2 pt on focus

struct HubTextField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String?
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(HubColor.tertiary)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(HubColor.tertiary))
                .textFieldStyle(.plain)
                .font(Font(SFFont.text(.sm)))
                .foregroundStyle(HubColor.foreground)
                .focused($focused)
                .onSubmit(onSubmit)
            if symbol != nil, !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(HubColor.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: SFMetrics.Controls.inputHeight)
        .background(RoundedRectangle(cornerRadius: SFMetrics.Controls.inputRadius, style: .continuous).fill(HubColor.card))
        .overlay(RoundedRectangle(cornerRadius: SFMetrics.Controls.inputRadius, style: .continuous)
            .strokeBorder(focused ? HubColor.neutral500 : HubColor.border, lineWidth: focused ? 2 : 1))
    }
}

/// A multi-line editor in the input style.
struct HubTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).hubText(.sm, .regular, HubColor.tertiary).padding(.horizontal, 12).padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(Font(SFFont.text(.sm)))
                .foregroundStyle(HubColor.foreground)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
        }
        .frame(minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: SFMetrics.Controls.inputRadius, style: .continuous).fill(HubColor.card))
        .overlay(RoundedRectangle(cornerRadius: SFMetrics.Controls.inputRadius, style: .continuous)
            .strokeBorder(focused ? HubColor.neutral500 : HubColor.border, lineWidth: focused ? 2 : 1))
    }
}

// MARK: - Key pills (§3.3)

struct KeyPill: View {
    let label: String
    var large = false
    var lit = false

    var body: some View {
        Text(label)
            .font(.system(size: large ? 22 : 13, weight: large ? .semibold : .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(lit ? Color.white : HubColor.keyInk)
            .padding(.horizontal, large ? 22 : 8)
            .frame(minWidth: large ? 72 : nil, minHeight: large ? 64 : SFMetrics.Hub.keyPillHeight)
            .background(RoundedRectangle(cornerRadius: large ? 12 : 4, style: .continuous)
                .fill(lit ? HubColor.dawnStrong : HubColor.keyFill)
                .shadow(color: lit ? HubColor.dawnStrong.opacity(0.4) : HubColor.keyEdge, radius: 0, y: large ? 4 : 2))
            .overlay(RoundedRectangle(cornerRadius: large ? 12 : 4, style: .continuous)
                .strokeBorder(lit ? Color.clear : HubColor.keyBorder))
            .animation(.easeOut(duration: 0.1), value: lit)
    }
}

/// A chord as key pills joined by "+" (§3.3: 6 pt margins, neutral-600).
struct ChordView: View {
    let chord: KeyChord

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(HubFormat.keyLabels(chord).enumerated()), id: \.offset) { index, label in
                if index > 0 { Text("+").hubText(.xs, .regular, HubColor.tertiary) }
                KeyPill(label: label)
            }
        }
        .fixedSize()
    }
}

// MARK: - Containers

/// Settings card (§4.2): padding 20, radius 12, tertiary fill.
struct HubCard<Content: View>: View {
    var padding: CGFloat = 20
    var spacing: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SFMetrics.Radius.lg, style: .continuous).fill(HubColor.backgroundTertiary))
    }
}

/// A bordered list container (History §11 gap 1: bordered sections, radius 16) with rows separated by 1 pt rules.
struct BorderedList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(HubColor.border).frame(height: 1) }
                row(item)
            }
        }
        .background(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous).fill(HubColor.background))
        .clipShape(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous).strokeBorder(HubColor.border))
    }
}

extension View {
    /// The bordered-list look around a single block of content.
    func borderedBox() -> some View {
        background(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous).fill(HubColor.background))
            .overlay(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous).strokeBorder(HubColor.border))
    }
}

@MainActor
enum Clipboard {
    /// Through InsertionKit when it is installed (it marks the item transient), else the general pasteboard.
    static func copy(_ text: String) {
        if let insertion = Services.insertion {
            insertion.copyToClipboard(text)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

/// A settings row (§4.2): label 15/20 550, description 15/20 tertiary, control column 164 wide on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    var controlWidth: CGFloat = 164
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).hubText(.sm, .emphasis)
                if let detail { Text(detail).hubText(.sm, .regular, HubColor.tertiary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { control }.frame(minWidth: controlWidth, alignment: .trailing)
        }
        .frame(minHeight: 36)
    }
}

/// A 1 pt rule.
struct Rule: View {
    var body: some View { Rectangle().fill(HubColor.border).frame(height: 1) }
}

/// Small chip (§10.4 generic chip): 12/20 550, padding 3 8, radius 8.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = HubColor.neutral600
    var fill: Color = HubColor.backgroundSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text)
        }
        .font(Font(SFFont.text(.xs, weight: SFFont.emphasisWeight)))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    }
}

/// A filter chip that can be selected.
struct FilterChip: View {
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count { Text("\(count)").foregroundStyle(selected ? HubColor.primaryForeground.opacity(0.7) : HubColor.tertiary) }
            }
            .font(Font(SFFont.text(.sm, weight: SFFont.emphasisWeight)))
            .foregroundStyle(selected ? HubColor.primaryForeground : HubColor.foreground)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(selected ? HubColor.primary : (hovering ? HubColor.hover : HubColor.backgroundTertiary)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Centered empty state.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(HubColor.neutral600)
                .frame(width: 52, height: 52)
                .background(Circle().fill(HubColor.backgroundTertiary))
            VStack(spacing: 4) {
                Text(title).hubText(.md, .strong)
                Text(message).hubText(.sm, .regular, HubColor.tertiary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(HubButtonStyle(variant: .primary)).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// A thin progress bar.
struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 4
    var tint: Color = HubColor.foreground
    var track: Color = HubColor.hover

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// The Super Flow mark: five rounded bars in a soft waveform (scripts/make-icon.swift).
struct BrandMark: View {
    var height: CGFloat = 18
    var color: Color = HubColor.foreground

    var body: some View {
        let bar = height * 0.147, gap = height * 0.095
        HStack(alignment: .center, spacing: gap) {
            ForEach([0.52, 0.79, 1.0, 0.79, 0.52], id: \.self) { h in
                Capsule().fill(color).frame(width: bar, height: height * h)
            }
        }
        .frame(height: height)
    }
}

/// A selection menu with a custom label (§4.2 inline input look) that pops a native menu.
struct MenuPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var width: CGFloat = 164

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            Text(options.first { $0.value == selection }?.title ?? "")
        }
        .menuStyle(.button)
        .buttonStyle(MenuLabelStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: width, alignment: .trailing)
    }
}

private struct MenuLabelStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.label.lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(HubColor.tertiary)
        }
        .font(Font(SFFont.text(.sm)))
        .foregroundStyle(HubColor.foreground)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(HubColor.card))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(HubColor.border))
        .contentShape(Rectangle())
    }
}

/// A checkbox (§10.1 tasks): 16 × 16, 1.5 pt border, radius 4; done is dawn-700 with a white check.
struct CheckBox: View {
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(checked ? HubColor.dawnStrong : HubColor.card)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(checked ? HubColor.dawnStrong : HubColor.neutral500.opacity(0.45), lineWidth: 1.5)
                if checked { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(checked ? "Completed" : "Not completed")
    }
}

/// A row that tints on hover and reveals trailing actions.
struct HoverRow<Content: View>: View {
    var padding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 12)
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? HubColor.backgroundTertiary : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// Tabs with a sliding 2 pt underline over a 1 pt rule (§10.1 tab bar): 15/20 600, tertiary until selected.
struct UnderlineTabs<Value: Hashable>: View {
    let tabs: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var underline

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ForEach(tabs, id: \.value) { tab in
                let selected = tab.value == selection
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 1)) { selection = tab.value }
                } label: {
                    Text(tab.title).hubText(.sm, .strong, selected ? HubColor.foreground : HubColor.neutral500.opacity(0.8))
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(HubColor.foreground).frame(height: 2).matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { Rule() }
    }
}

extension View {
    /// Long-form reading text (§10.1 editor body): 15 pt on a 28 pt line.
    func hubBody(_ color: Color = HubColor.foreground, weight: HubWeight = .regular) -> some View {
        let font = SFFont.text(.sm, weight: weight.ns)
        return self.font(Font(font)).foregroundStyle(color).lineSpacing(HubType.extraLeading(font, 26))
    }
}

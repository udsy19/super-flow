import AppKit
import SuperFlowCore

/// Fonts and colours of the bar's text and controls (ui-reference.md §2.5, §2.10–2.13). The bar always uses the
/// light-theme values: it is black on every appearance (§1.2).
public enum FlowBarStyle {
    static let label = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let labelRegular = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let timer = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    static let languageCode = NSFont.systemFont(ofSize: 10, weight: .semibold)
    static let tooltip = SFFont.text(.sm)
    static let tooltipBold = SFFont.text(.sm, weight: .bold)
    static let cardTitle = SFFont.text(.sm, weight: .semibold)
    static let cardTitleCondensed = SFFont.text(.sm, weight: SFFont.emphasisWeight)
    static let cardBody = SFFont.text(.sm)
    static let button = SFFont.text(.sm, weight: .semibold)
    static let liveText = SFFont.text(.md)
    static let lineHeight: CGFloat = 20

    static let fill = SFMetrics.FlowBar.fill
    static let rim = SFMetrics.FlowBar.border
    static let secondaryText = SFColor.vast300
    static let titleText = SFColor.sand50
    static let accentText = SFColor.signal500
    static let timerText = SFColor.vast300
    static let progressFill = SFColor.vast900.withAlphaComponent(0.5)
    static let completedHoverFill = NSColor(hex: "#4a4a4a")
    static let condensedFill = SFColor.vast950
    static let softDark = SFColor.vast600
    static let softDarkVast = NSColor(hex: "#2a2a29")
    static let primaryButton = SFColor.lumen

    static func attributes(_ font: NSFont, _ color: NSColor, lineHeight: CGFloat? = nil, wraps: Bool = false) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        if let lineHeight { style.minimumLineHeight = lineHeight; style.maximumLineHeight = lineHeight }
        style.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    /// Single-line text width, rounded up to whole points.
    static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    /// Wrapped text height for a width, at the line height.
    static func height(_ text: String, _ font: NSFont, width: CGFloat, lineHeight: CGFloat = lineHeight, maxLines: Int = .max) -> CGFloat {
        let s = NSAttributedString(string: text, attributes: attributes(font, .white, lineHeight: lineHeight, wraps: true))
        let h = s.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
        let lines = max(1, Int((h / lineHeight).rounded()))
        return CGFloat(min(lines, maxLines)) * lineHeight
    }
}

/// What the pill itself looks like: the part every state change animates with the 100 ms snap (§2.3).
public struct PillLook: Equatable {
    public var radius: CGFloat
    public var fill: NSColor
    public var border: NSColor
    public var borderWidth: CGFloat
    public var opacity: CGFloat
}

/// Things drawn inside or beside the pill.
public enum FlowBarItemKind: Hashable, Sendable {
    case mic, waveform, meetingWaveform, spinner, cancel, finish, stop, flushSpinner, timer, label, sparkle, progressFill
}

/// A card above the bar: the notification, the meeting prompt or the live text (§2.12, §2.13).
public struct FlowBarCardLayout: Equatable {
    public enum ButtonStyle: Equatable { case ghost, softDark, softDarkVast, primary, condensed }
    public struct Button: Equatable {
        public var element: FlowBarElement
        public var title: String
        public var rect: CGRect
        public var style: ButtonStyle
    }
    public var frame: CGRect
    public var radius: CGFloat
    public var fill: NSColor
    public var icon: CGRect?
    public var title: CGRect?
    public var subtitle: CGRect?
    public var buttons: [Button] = []
    public var close: CGRect?
    /// The 3 pt countdown track along the bottom edge.
    public var progress: CGRect?
}

/// Where everything sits in the bar's window for one scene (§2.2–2.4, §2.9–2.13). Pure geometry: the canvas draws
/// from it, hit-tests with it, and the self-tests check its numbers.
public struct FlowBarFrames: Equatable {
    public struct Item: Equatable {
        public var kind: FlowBarItemKind
        public var rect: CGRect
    }

    public var pill: CGRect = .zero
    public var look = PillLook(radius: SFMetrics.FlowBar.restingRadius, fill: SFMetrics.FlowBar.restingFill,
                               border: SFMetrics.FlowBar.restingBorder, borderWidth: 1, opacity: 0)
    /// Opacity of the pill's content row (.4 while a meeting wraps up, §10.2).
    public var contentOpacity: CGFloat = 1
    public var items: [Item] = []
    public var pickers: [FlowBarPicker: CGRect] = [:]
    public var notification: FlowBarCardLayout?
    public var prompt: FlowBarCardLayout?
    public var liveText: FlowBarCardLayout?
    public var tooltip: CGRect?
    /// Where the pointer counts as over the bar; everywhere else clicks pass through to the apps below.
    public var hotRects: [CGRect] = []

    public func item(_ kind: FlowBarItemKind) -> CGRect? { items.first { $0.kind == kind }?.rect }

    /// The interactive element under a point (window coordinates), front-most first.
    public func element(at p: CGPoint, in scene: FlowBarScene) -> FlowBarElement? {
        for card in [notification, prompt].compactMap({ $0 }) {
            for button in card.buttons where button.rect.insetBy(dx: -2, dy: -2).contains(p) { return button.element }
            if let close = card.close, close.insetBy(dx: -6, dy: -6).contains(p), let id = scene.notification?.id { return .cardClose(id: id) }
        }
        for (picker, rect) in pickers where rect.contains(p) { return .picker(picker) }
        switch scene.pill {
        case .handsFree:
            if let r = item(.cancel), r.insetBy(dx: -4, dy: -6).contains(p) { return .cancel }
            if let r = item(.finish), r.insetBy(dx: -4, dy: -6).contains(p) { return .finish }
        case .meeting:
            if let r = item(.stop), r.insetBy(dx: -5, dy: -5).contains(p) { return .meetingStop }
            if pill.contains(p) { return .meetingBody }
        default: break
        }
        if scene.pill != .hidden, scene.pill != .resting, pill.insetBy(dx: -2, dy: -2).contains(p) { return .pill }
        return nil
    }
}

public enum FlowBarLayout {
    typealias M = SFMetrics.FlowBar
    /// Pill bottom edge above the usable area, or inset from a side edge (§2.2).
    static let gapAboveBar: CGFloat = 12
    static let cardGap: CGFloat = 8

    // MARK: Pill

    /// The pill's look per state (§2.4, §10.2).
    public static func look(for scene: FlowBarScene) -> PillLook {
        let hovered = scene.hovered
        var look = PillLook(radius: M.radius, fill: M.fill, border: M.border, borderWidth: M.borderWidth, opacity: 1)
        switch scene.pill {
        case .hidden:
            look = PillLook(radius: M.restingRadius, fill: M.restingFill, border: M.restingBorder, borderWidth: 1, opacity: 0)
        case .resting:
            look = PillLook(radius: M.restingRadius, fill: M.restingFill, border: M.restingBorder, borderWidth: 1, opacity: 1)
        case .ready:
            if hovered == .pill { look.fill = M.hoverFill; look.border = M.hoverBorder }
        case .error:
            look.border = M.errorBorder; look.borderWidth = M.errorBorderWidth
        case .transformCompleted, .cleanupCompleted:
            if hovered == .pill { look.fill = FlowBarStyle.completedHoverFill; look.border = M.hoverBorder }
        case .meeting(let phase, _):
            look.borderWidth = M.meetingBorderWidth
            switch phase {
            case .pending: look.border = M.meetingPendingBorder
            case .reconnecting: look.border = M.meetingReconnectingBorder
            case .recording, .stopping: look.border = M.meetingBorder
            }
            if hovered == .meetingBody || hovered == .meetingStop { look.fill = M.hoverFill; look.border = M.hoverBorder }
        default:
            break
        }
        if scene.commandMode, scene.isListening || scene.pill == .processing { look.border = M.commandModeBorder }
        return look
    }

    /// A content item's size on the bottom edge (main axis horizontal).
    static func size(_ kind: FlowBarItemKind, scene: FlowBarScene, vertical: Bool) -> CGSize {
        let wave = CGSize(width: 46, height: SFMetrics.Waveform.containerHeight)
        switch kind {
        case .mic: return M.micGlyphSize
        case .waveform: return vertical ? CGSize(width: wave.height, height: wave.width) : wave
        case .meetingWaveform: return CGSize(width: SFMetrics.Waveform.meetingBox, height: SFMetrics.Waveform.meetingBox)
        case .spinner, .flushSpinner: return CGSize(width: SFMetrics.Spinner.size, height: SFMetrics.Spinner.size)
        case .cancel, .finish: return CGSize(width: M.handsFreeButtonSize, height: M.handsFreeButtonSize)
        case .stop: return CGSize(width: M.stopButtonSize, height: M.stopButtonSize)
        case .sparkle: return CGSize(width: 14, height: 14)
        case .timer: return CGSize(width: FlowBarStyle.width(timerText(scene) ?? "0:00", FlowBarStyle.timer), height: FlowBarStyle.lineHeight)
        case .label:
            let (a, b) = labelText(scene)
            let font = labelFont(scene)
            return CGSize(width: FlowBarStyle.width(a + b, font), height: FlowBarStyle.lineHeight)
        case .progressFill: return .zero
        }
    }

    static func labelFont(_ scene: FlowBarScene) -> NSFont {
        switch scene.pill {
        case .transformCompleted, .cleanupCompleted: FlowBarStyle.labelRegular
        default: FlowBarStyle.label
        }
    }

    /// The pill's label in two runs: the main words and an accent ("Getting ready…" + " 40%", "Done." + " See changes").
    public static func labelText(_ scene: FlowBarScene) -> (String, String) {
        switch scene.pill {
        case .preparing(let fraction): (FlowBarCopy.gettingReady, fraction > 0 ? " " + FlowBarCopy.percent(fraction) : "")
        case .transformProcessing(let label, _): (label, "")
        case .transformCompleted: (FlowBarCopy.transformDone, FlowBarCopy.seeChanges)
        case .cleanupCompleted: (FlowBarCopy.cleanedUp, FlowBarCopy.seeWhatChanged)
        default: ("", "")
        }
    }

    public static func timerText(_ scene: FlowBarScene) -> String? {
        switch scene.pill {
        case .handsFree(let elapsed): FlowBarMotion.elapsed(elapsed)
        case .meeting(.pending, _): nil
        case .meeting(_, let elapsed): FlowBarMotion.elapsed(elapsed)
        default: nil
        }
    }

    /// The content row: items in order with the gap before each, plus the pill's main length (nil = fit content)
    /// and padding along the main axis.
    static func row(for scene: FlowBarScene, vertical: Bool) -> (items: [(FlowBarItemKind, CGFloat)], main: CGFloat?, padding: CGFloat) {
        switch scene.pill {
        case .hidden, .resting: return ([], M.restingSize.width, 0)
        case .ready: return ([(.mic, 0)], M.readySize.width, 0)
        case .initializing, .pushToTalk: return ([(.waveform, 0)], M.pushToTalkSize.width, 0)
        case .handsFree:
            let timerSize = size(.timer, scene: scene, vertical: vertical)
            let timer = vertical ? timerSize.height : timerSize.width
            // The timer sits after the waveform with the same 8 pt of air on both sides as the bars have (§2.6 box padding).
            return ([(.cancel, 0), (.waveform, M.handsFreeRowGap), (.timer, M.handsFreeRowGap), (.finish, 2 * M.handsFreeRowGap)],
                    M.handsFreeSize.width + 2 * M.handsFreeRowGap + timer, 0)
        case .processing: return ([(.waveform, 0), (.spinner, M.processingRowGap)], M.processingSize.width, 12)
        case .error: return ([(.waveform, 0)], M.errorSize.width, 6)
        case .preparing: return ([(.progressFill, 0), (.label, 0)], nil, 14)
        case .transformProcessing: return ([(.progressFill, 0), (.label, 0), (.spinner, 8)], M.transformProcessingSize.width, 12)
        case .transformCompleted: return ([(.sparkle, 0), (.label, 4)], M.transformCompletedSize.width, 12)
        case .cleanupCompleted: return ([(.sparkle, 0), (.label, 4)], nil, 12)
        case .meeting(let phase, _):
            switch phase {
            case .pending: return ([(.meetingWaveform, 0), (.stop, M.meetingRowGap)], nil, 5)
            case .stopping: return ([(.meetingWaveform, 0), (.timer, 8), (.flushSpinner, M.meetingRowGap)], nil, 5)
            case .recording, .reconnecting: return ([(.meetingWaveform, 0), (.timer, 8), (.stop, M.meetingRowGap)], nil, 5)
            }
        }
    }

    /// States whose text keeps them horizontal on the side edges.
    static func staysHorizontal(_ pill: FlowBarScene.Pill) -> Bool {
        switch pill {
        case .preparing, .transformProcessing, .transformCompleted, .cleanupCompleted: true
        default: false
        }
    }

    // MARK: Window

    /// The window's frame for a dock edge inside the usable area (§2.2): 512 × 614 centred on the bottom edge, or
    /// 490 × min(1144, height) flush to a side, vertically centred.
    public static func windowFrame(edge: FlowBarEdge, visibleFrame vf: CGRect) -> CGRect {
        switch edge {
        case .bottom:
            let size = M.bottomWindowSize
            return CGRect(x: (vf.midX - size.width / 2).rounded(), y: vf.minY, width: size.width, height: size.height)
        case .left, .right:
            let height = min(M.sideWindowMaxHeight, vf.height)
            let x = edge == .left ? vf.minX : vf.maxX - M.sideWindowWidth
            return CGRect(x: x, y: (vf.midY - height / 2).rounded(), width: M.sideWindowWidth, height: height)
        }
    }

    // MARK: Frames

    public static func frames(for scene: FlowBarScene, in bounds: CGRect) -> FlowBarFrames {
        var f = FlowBarFrames()
        let vertical = scene.edge != .bottom && !staysHorizontal(scene.pill)
        let row = row(for: scene, vertical: vertical)
        let contents = row.items.filter { $0.0 != .progressFill }
        let sizes = contents.map { size($0.0, scene: scene, vertical: vertical) }
        let contentMain = zip(contents, sizes).reduce(CGFloat(0)) { $0 + $1.0.1 + (vertical ? $1.1.height : $1.1.width) }
        let main = row.main ?? (contentMain + 2 * row.padding)
        let crossContent = sizes.map { vertical ? $0.width : $0.height }.max() ?? 0
        let isResting = scene.pill == .resting || scene.pill == .hidden
        let cross = isResting ? M.restingSize.height : max(M.height, crossContent + 4)
        let pillSize = vertical ? CGSize(width: cross, height: main) : CGSize(width: main, height: cross)
        f.pill = pillRect(size: pillSize, edge: scene.edge, in: bounds)
        f.look = look(for: scene)
        if case .meeting(.stopping, _) = scene.pill { f.contentOpacity = 0.4 }

        // Content, centred along the main axis.
        var cursor = vertical ? f.pill.midY + contentMain / 2 : f.pill.midX - contentMain / 2
        for ((kind, gap), s) in zip(contents, sizes) {
            if vertical {
                cursor -= gap
                f.items.append(.init(kind: kind, rect: CGRect(x: f.pill.midX - s.width / 2, y: cursor - s.height, width: s.width, height: s.height)))
                cursor -= s.height
            } else {
                cursor += gap
                f.items.append(.init(kind: kind, rect: CGRect(x: cursor, y: f.pill.midY - s.height / 2, width: s.width, height: s.height)))
                cursor += s.width
            }
        }
        if row.items.contains(where: { $0.0 == .progressFill }) { f.items.insert(.init(kind: .progressFill, rect: f.pill), at: 0) }
        // Transform progress keeps its label left and the spinner right (§2.11).
        if case .transformProcessing = scene.pill, let i = f.items.firstIndex(where: { $0.kind == .label }),
           let j = f.items.firstIndex(where: { $0.kind == .spinner }) {
            f.items[i].rect.origin.x = f.pill.minX + row.padding
            f.items[j].rect.origin.x = f.pill.maxX - row.padding - f.items[j].rect.width
        }

        // Pickers beside the ready pill (§2.9): 8 from the pill, 2 apart, the pill never moves.
        if scene.showsPickers {
            let d = M.pickerSize
            for (index, picker) in FlowBarPicker.leading.reversed().enumerated() {
                let offset = 8 + CGFloat(index) * (d + M.pickerGap)
                f.pickers[picker] = scene.edge == .bottom
                    ? CGRect(x: f.pill.minX - offset - d, y: f.pill.midY - d / 2, width: d, height: d)
                    : CGRect(x: f.pill.midX - d / 2, y: f.pill.maxY + offset, width: d, height: d)
            }
            for (index, picker) in FlowBarPicker.trailing.enumerated() {
                let offset = 8 + CGFloat(index) * (d + M.pickerGap)
                f.pickers[picker] = scene.edge == .bottom
                    ? CGRect(x: f.pill.maxX + offset, y: f.pill.midY - d / 2, width: d, height: d)
                    : CGRect(x: f.pill.midX - d / 2, y: f.pill.minY - offset - d, width: d, height: d)
            }
        }

        // Hot area: the hover zone around the pill (§2.3), the pickers, the cards.
        if scene.pill != .hidden {
            var zone = f.pickers.values.reduce(f.pill) { $0.union($1) }
            zone = zone.insetBy(dx: scene.edge == .bottom ? -19 : -6, dy: scene.edge == .bottom ? -6 : -19)
            if scene.pill == .ready { zone = zone.insetBy(dx: -12, dy: -12) }
            switch scene.edge {
            case .bottom: zone = CGRect(x: zone.minX, y: bounds.minY + 8, width: zone.width, height: max(40, zone.maxY - bounds.minY - 8))
            case .left: zone = CGRect(x: bounds.minX, y: zone.minY, width: max(40, zone.maxX - bounds.minX), height: zone.height)
            case .right: zone = CGRect(x: min(zone.minX, bounds.maxX - 40), y: zone.minY, width: bounds.maxX - min(zone.minX, bounds.maxX - 40), height: zone.height)
            }
            f.hotRects.append(zone)
        }

        // Cards, nearest first: live text, the meeting prompt, the notification.
        var anchor = firstCardAnchor(pill: f.pill, edge: scene.edge, bounds: bounds)
        if scene.liveText != nil {
            f.liveText = FlowBarCardLayout(frame: place(M.liveTextSize, at: &anchor, edge: scene.edge, pill: f.pill),
                                           radius: M.liveTextRadius, fill: FlowBarStyle.fill)
        }
        if let prompt = scene.prompt {
            var card = promptLayout(prompt)
            card = offset(card, to: place(card.frame.size, at: &anchor, edge: scene.edge, pill: f.pill))
            f.prompt = card
        }
        if let notification = scene.notification {
            var card = notificationLayout(notification)
            card = offset(card, to: place(card.frame.size, at: &anchor, edge: scene.edge, pill: f.pill))
            f.notification = card
        }
        f.hotRects += [f.notification, f.prompt].compactMap { $0?.frame }

        // Tooltip for the hovered element (§2.10).
        if let runs = scene.tooltip, let anchorRect = anchorRect(for: scene.hovered, in: f) {
            let text = runs.map(\.text).joined()
            let size = CGSize(width: FlowBarStyle.width(text, FlowBarStyle.tooltip) + 2 * M.tooltipPadding.width + 4,
                              height: FlowBarStyle.lineHeight + 2 * M.tooltipPadding.height + 2)
            let offset: CGFloat = scene.hovered == .cancel || scene.hovered == .finish ? 10 : scene.hovered == .meetingStop ? 9 : M.tooltipOffset
            var r: CGRect
            switch scene.edge {
            case .bottom: r = CGRect(x: anchorRect.midX - size.width / 2, y: anchorRect.maxY + offset, width: size.width, height: size.height)
            case .left: r = CGRect(x: anchorRect.maxX + offset, y: anchorRect.midY - size.height / 2, width: size.width, height: size.height)
            case .right: r = CGRect(x: anchorRect.minX - offset - size.width, y: anchorRect.midY - size.height / 2, width: size.width, height: size.height)
            }
            r.origin.x = min(max(r.minX, bounds.minX + 4), bounds.maxX - 4 - r.width).rounded()
            r.origin.y = r.minY.rounded()
            f.tooltip = r
        }
        return f
    }

    static func pillRect(size: CGSize, edge: FlowBarEdge, in bounds: CGRect) -> CGRect {
        switch edge {
        case .bottom:
            return CGRect(x: bounds.midX - size.width / 2, y: bounds.minY + M.bottomInset, width: size.width, height: size.height)
        case .left:
            return CGRect(x: bounds.minX + M.sideInset, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return CGRect(x: bounds.maxX - M.sideInset - size.width, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    /// Cards clear an active (30 pt) pill by 12 pt whatever the current pill size, so they never jump.
    static func firstCardAnchor(pill: CGRect, edge: FlowBarEdge, bounds: CGRect) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: bounds.midX, y: bounds.minY + M.bottomInset + M.height + gapAboveBar)
        case .left: CGPoint(x: bounds.minX + M.sideInset + M.height + gapAboveBar, y: pill.midY)
        case .right: CGPoint(x: bounds.maxX - M.sideInset - M.height - gapAboveBar, y: pill.midY)
        }
    }

    /// Places a card at the anchor and moves the anchor past it.
    static func place(_ size: CGSize, at anchor: inout CGPoint, edge: FlowBarEdge, pill: CGRect) -> CGRect {
        switch edge {
        case .bottom:
            let r = CGRect(x: (anchor.x - size.width / 2).rounded(), y: anchor.y, width: size.width, height: size.height)
            anchor.y = r.maxY + cardGap
            return r
        case .left, .right:
            let x = edge == .left ? anchor.x : anchor.x - size.width
            let r = CGRect(x: x, y: (anchor.y - size.height / 2).rounded(), width: size.width, height: size.height)
            anchor.y = r.maxY + cardGap + size.height / 2
            return r
        }
    }

    static func offset(_ card: FlowBarCardLayout, to frame: CGRect) -> FlowBarCardLayout {
        let dx = frame.minX - card.frame.minX, dy = frame.minY - card.frame.minY
        func move(_ r: CGRect?) -> CGRect? { r?.offsetBy(dx: dx, dy: dy) }
        var c = card
        c.frame = frame
        c.icon = move(c.icon); c.title = move(c.title); c.subtitle = move(c.subtitle); c.close = move(c.close); c.progress = move(c.progress)
        c.buttons = c.buttons.map { var b = $0; b.rect = b.rect.offsetBy(dx: dx, dy: dy); return b }
        return c
    }

    static func anchorRect(for element: FlowBarElement?, in f: FlowBarFrames) -> CGRect? {
        switch element {
        case .pill?, .meetingBody?: f.pill
        case .cancel?: f.item(.cancel)
        case .finish?: f.item(.finish)
        case .meetingStop?: f.item(.stop)
        case .picker(let p)?: f.pickers[p]
        default: nil
        }
    }

    // MARK: Cards (origin at 0,0; placed by `frames`)

    static func buttonSize(_ title: String, _ style: FlowBarCardLayout.ButtonStyle) -> CGSize {
        let w = FlowBarStyle.width(title, FlowBarStyle.button)
        switch style {
        case .ghost: return CGSize(width: w, height: 32)
        case .condensed: return CGSize(width: FlowBarStyle.width(title, FlowBarStyle.cardBody) + 20, height: 32)
        case .softDark, .softDarkVast, .primary: return CGSize(width: w + 24, height: 36)
        }
    }

    /// Notification cards (§2.12): mini is one line, condensed a dark strip with a countdown, the rest standard
    /// cards with a status icon for error, alert and success.
    static func notificationLayout(_ n: FlowBarNotification) -> FlowBarCardLayout {
        let maxW = M.notificationMaxSize.width
        switch n.variant {
        case .mini:
            let buttons = n.actions.map { ($0, buttonSize($0, .ghost)) }
            let actionsW = buttons.reduce(CGFloat(0)) { $0 + $1.1.width + 12 }
            let titleW = min(FlowBarStyle.width(n.title, FlowBarStyle.cardBody), maxW - 32 - actionsW)
            let size = CGSize(width: 16 + titleW + actionsW + 16, height: 44)
            var card = FlowBarCardLayout(frame: CGRect(origin: .zero, size: size), radius: M.notificationMiniRadius, fill: FlowBarStyle.fill)
            card.title = CGRect(x: 16, y: 12, width: titleW, height: 20)
            var x = 16 + titleW
            for (index, (title, s)) in buttons.enumerated() {
                x += 12
                card.buttons.append(.init(element: .cardAction(id: n.id, index: index), title: title,
                                          rect: CGRect(x: x, y: (size.height - s.height) / 2, width: s.width, height: s.height), style: .ghost))
                x += s.width
            }
            return card
        case .condensed:
            let buttons = n.actions.map { ($0, buttonSize($0, .condensed)) }
            let actionsW = buttons.reduce(CGFloat(0)) { $0 + $1.1.width } + CGFloat(max(0, buttons.count - 1)) * 8
            let titleMax = maxW - 32 - (actionsW > 0 ? actionsW + 16 : 0)
            let titleW = min(FlowBarStyle.width(n.title, FlowBarStyle.cardTitleCondensed), titleMax)
            let titleH = FlowBarStyle.height(n.title, FlowBarStyle.cardTitleCondensed, width: titleW, maxLines: 2)
            let height = max(titleH, buttons.isEmpty ? 0 : 32) + 16 + (n.timeout != nil ? 3 : 0)
            let size = CGSize(width: 16 + titleW + (actionsW > 0 ? 16 + actionsW : 0) + 16, height: max(height, 44))
            var card = FlowBarCardLayout(frame: CGRect(origin: .zero, size: size), radius: M.notificationRadius, fill: FlowBarStyle.condensedFill)
            let mid = (size.height + (n.timeout != nil ? 3 : 0)) / 2
            card.title = CGRect(x: 16, y: mid - titleH / 2, width: titleW, height: titleH)
            var x = size.width - 16 - actionsW
            for (index, (title, s)) in buttons.enumerated() {
                card.buttons.append(.init(element: .cardAction(id: n.id, index: index), title: title,
                                          rect: CGRect(x: x, y: mid - s.height / 2, width: s.width, height: s.height), style: .condensed))
                x += s.width + 8
            }
            if n.timeout != nil { card.progress = CGRect(x: 0, y: 0, width: size.width, height: M.notificationProgressHeight) }
            return card
        case .standard, .error, .alert, .success:
            let hasIcon = n.variant != .standard
            let pad: CGFloat = 20
            let closeSpace: CGFloat = 28
            let titleNatural = FlowBarStyle.width(n.title, FlowBarStyle.cardTitle) + (hasIcon ? 24 : 0) + closeSpace
            let subtitleNatural = n.subtitle.map { FlowBarStyle.width($0, FlowBarStyle.cardBody) } ?? 0
            let buttons = actionButtons(n.actions, id: n.id)
            let actionsW = buttons.reduce(CGFloat(0)) { $0 + $1.rect.width } + CGFloat(max(0, buttons.count - 1)) * 8
            let width = min(maxW, max(340, max(titleNatural, subtitleNatural, actionsW) + 2 * pad))
            let inner = width - 2 * pad
            let titleW = inner - (hasIcon ? 24 : 0) - closeSpace
            let titleH = FlowBarStyle.height(n.title, FlowBarStyle.cardTitle, width: titleW, maxLines: 2)
            let subH = n.subtitle.map { FlowBarStyle.height($0, FlowBarStyle.cardBody, width: inner, maxLines: 6) } ?? 0
            let actionsH: CGFloat = buttons.isEmpty ? 0 : 36
            var height = pad + titleH + (subH > 0 ? 8 + subH : 0) + (actionsH > 0 ? 16 + actionsH : 0) + pad
            height = min(height, M.notificationMaxSize.height)
            var card = FlowBarCardLayout(frame: CGRect(x: 0, y: 0, width: width, height: height), radius: M.notificationRadius, fill: FlowBarStyle.fill)
            var y = height - pad
            if hasIcon { card.icon = CGRect(x: pad, y: y - 18, width: 16, height: 16) }
            card.title = CGRect(x: pad + (hasIcon ? 24 : 0), y: y - titleH, width: titleW, height: titleH)
            card.close = CGRect(x: width - 16 - 16, y: height - 16 - 16, width: 16, height: 16)
            y -= titleH
            if subH > 0 { card.subtitle = CGRect(x: pad, y: y - 8 - subH, width: inner, height: subH); y -= 8 + subH }
            var x = width - pad - actionsW
            for b in buttons {
                var b = b
                b.rect.origin = CGPoint(x: x, y: pad)
                card.buttons.append(b)
                x += b.rect.width + 8
            }
            return card
        }
    }

    /// Ghost buttons first, the first action last as the soft-dark primary (macOS puts the default on the right).
    static func actionButtons(_ actions: [String], id: String) -> [FlowBarCardLayout.Button] {
        guard let first = actions.first else { return [] }
        let rest = actions.dropFirst().enumerated().map { offset, title in
            FlowBarCardLayout.Button(element: .cardAction(id: id, index: offset + 1), title: title,
                                     rect: CGRect(origin: .zero, size: buttonSize(title, .ghost)), style: .ghost)
        }
        let primary = FlowBarCardLayout.Button(element: .cardAction(id: id, index: 0), title: first,
                                               rect: CGRect(origin: .zero, size: buttonSize(first, .softDark)), style: .softDark)
        return rest.reversed().map { var b = $0; b.rect.size.height = 36; return b } + [primary]
    }

    /// The meeting-detected prompt (owner decision: always ask; §20.1): title, what was detected, three choices
    /// and a countdown along the bottom.
    static func promptLayout(_ prompt: MeetingPrompt) -> FlowBarCardLayout {
        let pad: CGFloat = 20
        let never = FlowBarCopy.dontAsk(prompt.platform)
        let record = buttonSize(FlowBarCopy.record, .primary)
        let notNow = buttonSize(FlowBarCopy.notNow, .softDarkVast)
        let neverW = FlowBarStyle.width(never, FlowBarStyle.cardBody)
        let actionsW = neverW + 16 + notNow.width + 8 + record.width
        let subtitle = FlowBarCopy.promptSubtitle(prompt)
        let titleW = FlowBarStyle.width(FlowBarCopy.promptTitle, FlowBarStyle.cardTitle) + 24
        let subtitleW = FlowBarStyle.width(subtitle, FlowBarStyle.cardBody)
        let width = min(M.notificationMaxSize.width, max(380, max(actionsW, titleW, subtitleW) + 2 * pad))
        let inner = width - 2 * pad
        let subH = FlowBarStyle.height(subtitle, FlowBarStyle.cardBody, width: inner, maxLines: 3)
        let height = pad + 20 + 4 + subH + 16 + 36 + pad
        var card = FlowBarCardLayout(frame: CGRect(x: 0, y: 0, width: width, height: height), radius: M.notificationRadius, fill: FlowBarStyle.fill)
        card.icon = CGRect(x: pad, y: height - pad - 18, width: 16, height: 16)
        card.title = CGRect(x: pad + 24, y: height - pad - 20, width: inner - 24, height: 20)
        card.subtitle = CGRect(x: pad, y: height - pad - 24 - subH, width: inner, height: subH)
        let recordRect = CGRect(x: width - pad - record.width, y: pad, width: record.width, height: record.height)
        let notNowRect = CGRect(x: recordRect.minX - 8 - notNow.width, y: pad, width: notNow.width, height: notNow.height)
        card.buttons = [
            .init(element: .prompt(.neverForApp), title: never, rect: CGRect(x: pad, y: pad, width: neverW, height: 36), style: .ghost),
            .init(element: .prompt(.notNow), title: FlowBarCopy.notNow, rect: notNowRect, style: .softDarkVast),
            .init(element: .prompt(.record), title: FlowBarCopy.record, rect: recordRect, style: .primary),
        ]
        card.progress = CGRect(x: 0, y: 0, width: width, height: M.notificationProgressHeight)
        return card
    }
}

import AppKit
import SuperFlowCore

// The view that draws the bar: one immediate-mode canvas over the transparent window, so on-screen frames and the
// offscreen renders (`cacheDisplay`) come from the same code. Every change animates as ui-reference.md asks: size,
// colour and radius with the 100 ms snap (§2.3), cards with the 420 ms spring (§2.12), tooltips 120/180 ms (§2.10).

protocol Lerpable: Equatable {
    static func lerp(_ a: Self, _ b: Self, _ t: CGFloat) -> Self
}

extension CGFloat: Lerpable {
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

extension CGRect: Lerpable {
    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: .lerp(a.minX, b.minX, t), y: .lerp(a.minY, b.minY, t), width: .lerp(a.width, b.width, t), height: .lerp(a.height, b.height, t))
    }
}

/// sRGB components, so colours interpolate.
struct RGBA: Lerpable {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.black
        r = c.redComponent; g = c.greenComponent; b = c.blueComponent; a = c.alphaComponent
    }
    var color: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    static func lerp(_ x: RGBA, _ y: RGBA, _ t: CGFloat) -> RGBA {
        var c = x
        c.r = .lerp(x.r, y.r, t); c.g = .lerp(x.g, y.g, t); c.b = .lerp(x.b, y.b, t); c.a = .lerp(x.a, y.a, t)
        return c
    }
}

struct PillGeometry: Lerpable {
    var rect: CGRect, radius: CGFloat, fill: RGBA, border: RGBA, borderWidth: CGFloat, opacity: CGFloat
    init(_ rect: CGRect, _ look: PillLook) {
        self.rect = rect; radius = look.radius; fill = RGBA(look.fill); border = RGBA(look.border)
        borderWidth = look.borderWidth; opacity = look.opacity
    }
    static func lerp(_ a: PillGeometry, _ b: PillGeometry, _ t: CGFloat) -> PillGeometry {
        var g = a
        g.rect = .lerp(a.rect, b.rect, t); g.radius = .lerp(a.radius, b.radius, t)
        g.fill = .lerp(a.fill, b.fill, t); g.border = .lerp(a.border, b.border, t)
        g.borderWidth = .lerp(a.borderWidth, b.borderWidth, t); g.opacity = .lerp(a.opacity, b.opacity, t)
        return g
    }
}

/// A value easing from one target to the next.
struct Tween<V: Lerpable> {
    private(set) var from: V
    private(set) var to: V
    private var start: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var curve = TimingCurve.linear

    init(_ value: V) { from = value; to = value }

    func value(at t: TimeInterval) -> V {
        guard duration > 0 else { return to }
        let p = (t - start) / duration
        if p >= 1 { return to }
        if p <= 0 { return from }
        return V.lerp(from, to, CGFloat(curve(p)))
    }

    func isSettled(at t: TimeInterval) -> Bool { duration <= 0 || t >= start + duration }

    mutating func set(_ target: V, at t: TimeInterval, duration: TimeInterval, curve: TimingCurve, delay: TimeInterval = 0) {
        guard target != to else { return }
        from = value(at: t); to = target; start = t + delay; self.duration = duration; self.curve = curve
        if duration <= 0 { from = target }
    }
}

@MainActor
final class FlowBarCanvas: NSView {
    private struct ItemAnim {
        var rect: Tween<CGRect>
        var presence: Tween<CGFloat>
        var removing = false
    }

    private enum CardContent: Equatable {
        case notification(FlowBarNotification, shownAt: Date?)
        case prompt(MeetingPrompt, shownAt: Date?)
        case live(String)

        /// Cards with a running countdown bar need a frame each tick.
        var hasCountdown: Bool {
            switch self {
            case .prompt: true
            case .notification(let n, _): n.variant == .condensed && n.timeout != nil
            case .live: false
            }
        }
    }

    private struct CardAnim {
        var layout: FlowBarCardLayout
        var content: CardContent
        var opacity: Tween<CGFloat>
        var scale: Tween<CGFloat>
        var lift: Tween<CGFloat>
        var removing = false
    }

    private struct TooltipAnim {
        var runs: [FlowBarCopy.Run] = []
        var rect = Tween(CGRect.zero)
        var opacity = Tween(CGFloat(0))
    }

    private(set) var scene = FlowBarScene()
    private(set) var frames = FlowBarFrames()
    /// Seconds since the reference date; the renders pin it.
    var clock: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    var reduceMotion = false
    var level = LevelSmoother()
    private var lastStep: TimeInterval?

    private var pill = Tween(PillGeometry(.zero, FlowBarFrames().look))
    private var contentOpacity = Tween(CGFloat(1))
    private var items: [FlowBarItemKind: ItemAnim] = [:]
    private var pickers: [FlowBarPicker: ItemAnim] = [:]
    private var cards: [String: CardAnim] = [:]
    private var tooltip = TooltipAnim()
    private var fill = Tween(CGFloat(0))
    /// When the reconnecting pulse began, so it starts from full opacity.
    private var reconnectingSince: TimeInterval?

    var onMouseDown: ((FlowBarElement?, NSEvent) -> Void)?
    var onMouseUp: ((FlowBarElement?, NSEvent) -> Void)?
    var onRightMouseDown: ((NSEvent) -> Void)?
    /// VoiceOver pressed an element.
    var onActivate: ((FlowBarElement) -> Void)?
    private var lastDirty = CGRect.zero

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Scene

    func apply(_ new: FlowBarScene, animated: Bool) {
        let t = clock()
        let old = scene
        scene = new
        frames = FlowBarLayout.frames(for: new, in: bounds)
        let a = animated

        let meetingChange: Bool = {
            if case .meeting = old.pill { return true }
            if case .meeting = new.pill { return true }
            return false
        }()
        let size = meetingChange ? (reduceMotion ? 0 : SFMotion.meetingSizeDuration) : SFMotion.snapDuration
        pill.set(PillGeometry(frames.pill, frames.look), at: t, duration: a ? size : 0, curve: .snap)
        contentOpacity.set(frames.contentOpacity, at: t, duration: a ? SFMotion.meetingContentFade : 0, curve: .ease)

        var present: [FlowBarItemKind: CGRect] = [:]
        for item in frames.items { present[item.kind] = item.rect }
        retarget(&items, present, at: t, duration: a ? size : 0)
        var shown: [FlowBarPicker: CGRect] = [:]
        for (picker, rect) in frames.pickers { shown[picker] = rect }
        retarget(&pickers, shown, at: t, duration: a ? SFMotion.snapDuration : 0)

        if case .meeting(.reconnecting, _) = new.pill {
            if reconnectingSince == nil { reconnectingSince = t }
        } else {
            reconnectingSince = nil
        }

        // Preparing and Transform progress fills.
        switch new.pill {
        case .preparing(let fraction):
            if case .preparing = old.pill { fill.set(CGFloat(fraction), at: t, duration: a ? SFMotion.materialDuration : 0, curve: .material) }
            else { fill.set(CGFloat(fraction), at: t, duration: 0, curve: .linear) }
        default: fill.set(0, at: t, duration: 0, curve: .linear)
        }

        // Cards.
        var next: [String: (FlowBarCardLayout, CardContent)] = [:]
        if let layout = frames.liveText, let text = new.liveText { next["live"] = (layout, .live(text)) }
        if let layout = frames.prompt, let prompt = new.prompt { next["prompt"] = (layout, .prompt(prompt, shownAt: new.promptShownAt)) }
        if let layout = frames.notification, let n = new.notification { next["n:" + n.id] = (layout, .notification(n, shownAt: new.notificationShownAt)) }
        for (key, value) in next {
            if var card = cards[key] {
                card.layout = value.0; card.content = value.1
                if card.removing {
                    card.removing = false
                    card.opacity.set(1, at: t, duration: a ? SFMotion.notificationShadowDuration : 0, curve: .ease)
                    card.scale.set(1, at: t, duration: a ? SFMotion.springMorphDuration : 0, curve: .spring)
                }
                cards[key] = card
            } else {
                var card = CardAnim(layout: value.0, content: value.1, opacity: Tween(a ? 0 : 1),
                                    scale: Tween(a && key != "live" ? 1.015 : 1), lift: Tween(a && key != "live" ? 1 : 0))
                card.opacity.set(1, at: t, duration: key == "live" ? 0.2 : SFMotion.notificationShadowDuration, curve: .ease)
                card.scale.set(1, at: t, duration: SFMotion.springMorphDuration, curve: .spring)
                card.lift.set(0, at: t, duration: SFMotion.springMorphDuration, curve: .spring)
                cards[key] = card
            }
        }
        for key in cards.keys where next[key] == nil {
            guard a else { cards[key] = nil; continue }
            cards[key]?.removing = true
            cards[key]?.opacity.set(0, at: t, duration: SFMotion.notificationShadowDuration, curve: .ease)
            if key != "live" { cards[key]?.scale.set(1.015, at: t, duration: SFMotion.springMorphDuration, curve: .spring) }
        }

        // Tooltip: 50 ms delay and a 120 ms fade the first time; slides 180 ms between elements.
        if let runs = new.tooltip, let rect = frames.tooltip {
            let visible = tooltip.opacity.to > 0
            if visible, a {
                tooltip.rect.set(rect, at: t, duration: reduceMotion ? 0 : SFMotion.tooltipSlide, curve: .ease)
            } else {
                tooltip.rect.set(rect, at: t, duration: 0, curve: .linear)
                tooltip.opacity.set(1, at: t, duration: a ? SFMotion.tooltipFade : 0, curve: .ease,
                                    delay: a ? SFMetrics.FlowBar.tooltipShowDelay : 0)
            }
            tooltip.runs = runs
        } else {
            tooltip.opacity.set(0, at: t, duration: a ? SFMotion.tooltipFade : 0, curve: .ease)
        }
        needsDisplay = true
    }

    private func retarget<K: Hashable>(_ anims: inout [K: ItemAnim], _ present: [K: CGRect], at t: TimeInterval, duration: TimeInterval) {
        for (key, rect) in present {
            if var anim = anims[key] {
                anim.rect.set(rect, at: t, duration: duration, curve: .snap)
                anim.presence.set(1, at: t, duration: duration, curve: .snap)
                anim.removing = false
                anims[key] = anim
            } else {
                var anim = ItemAnim(rect: Tween(rect), presence: Tween(duration > 0 ? 0 : 1))
                anim.presence.set(1, at: t, duration: duration, curve: .snap)
                anims[key] = anim
            }
        }
        for key in anims.keys where present[key] == nil {
            if duration > 0 {
                anims[key]?.removing = true
                anims[key]?.presence.set(0, at: t, duration: duration, curve: .snap)
            } else {
                anims[key] = nil
            }
        }
    }

    /// Advances the level smoother and drops finished exits; true while another frame would change the picture.
    func step() -> Bool {
        let t = clock()
        let dt = lastStep.map { t - $0 } ?? (1.0 / 60)
        lastStep = t
        level.step(dt: dt)
        items = items.filter { !($0.value.removing && $0.value.presence.isSettled(at: t)) }
        pickers = pickers.filter { !($0.value.removing && $0.value.presence.isSettled(at: t)) }
        cards = cards.filter { !($0.value.removing && $0.value.opacity.isSettled(at: t)) }
        let dirty = contentBounds
        setNeedsDisplay(dirty.union(lastDirty))
        lastDirty = dirty
        return isAnimating(at: t)
    }

    func isAnimating(at t: TimeInterval) -> Bool {
        if !pill.isSettled(at: t) || !contentOpacity.isSettled(at: t) || !fill.isSettled(at: t) { return true }
        if !tooltip.opacity.isSettled(at: t) || !tooltip.rect.isSettled(at: t) { return true }
        if items.values.contains(where: { !$0.presence.isSettled(at: t) || !$0.rect.isSettled(at: t) }) { return true }
        if pickers.values.contains(where: { !$0.presence.isSettled(at: t) }) { return true }
        if cards.values.contains(where: { !$0.opacity.isSettled(at: t) || !$0.scale.isSettled(at: t) || $0.content.hasCountdown }) { return true }
        switch scene.pill {
        case .initializing, .pushToTalk, .handsFree: return !level.isSettled || level.speaking
        case .meeting(let phase, _): return phase == .stopping || phase == .reconnecting || !level.isSettled || level.speaking
        case .processing, .transformProcessing: return true
        default: return false
        }
    }

    /// The pill's frame at this moment of its animation.
    var currentPillFrame: CGRect { pill.value(at: clock()).rect }

    /// Everything the current picture covers, for partial redraws.
    var contentBounds: CGRect {
        let t = clock()
        var r = pill.value(at: t).rect
        for p in pickers.values { r = r.union(p.rect.value(at: t)) }
        for c in cards.values { r = r.union(c.layout.frame) }
        if tooltip.opacity.value(at: t) > 0 { r = r.union(tooltip.rect.value(at: t)) }
        return r.insetBy(dx: -40, dy: -40).intersection(bounds)
    }

    // MARK: Pointer

    func element(at p: CGPoint) -> FlowBarElement? { frames.element(at: p, in: scene) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return frames.hotRects.contains { $0.contains(p) } ? self : nil
    }

    // MARK: Accessibility

    /// The clickable parts with their spoken names, for VoiceOver.
    var accessibleElements: [(FlowBarElement, CGRect, String)] {
        var list: [(FlowBarElement, CGRect, String)] = []
        switch scene.pill {
        case .ready: list.append((.pill, frames.pill, "Dictate"))
        case .handsFree:
            if let r = frames.item(.cancel) { list.append((.cancel, r, FlowBarCopy.cancel)) }
            if let r = frames.item(.finish) { list.append((.finish, r, FlowBarCopy.finish)) }
        case .meeting(let phase, _):
            list.append((.meetingBody, frames.pill, "Show notes"))
            if phase != .stopping, let r = frames.item(.stop) { list.append((.meetingStop, r, FlowBarCopy.stopNotetaker)) }
        default: break
        }
        var hover = scene
        for (picker, rect) in frames.pickers.sorted(by: { scene.edge == .bottom ? $0.value.minX < $1.value.minX : $0.value.maxY > $1.value.maxY }) {
            hover.hovered = .picker(picker)
            list.append((.picker(picker), rect, hover.tooltip?.map(\.text).joined() ?? picker.rawValue))
        }
        for card in [frames.prompt, frames.notification].compactMap({ $0 }) {
            for button in card.buttons { list.append((button.element, button.rect, button.title)) }
            if let close = card.close, let id = scene.notification?.id { list.append((.cardClose(id: id), close, "Dismiss notification")) }
        }
        return list
    }

    override func accessibilityChildren() -> [Any]? {
        accessibleElements.map { element, rect, label in
            let item = FlowBarAccessibilityElement()
            item.setAccessibilityRole(.button)
            item.setAccessibilityLabel(label)
            item.setAccessibilityParent(self)
            item.setAccessibilityFrame(NSAccessibility.screenRect(fromView: self, rect: rect))
            item.press = { [weak self] in self?.onActivate?(element) }
            return item
        }
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(element(at: convert(event.locationInWindow, from: nil)), event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(element(at: convert(event.locationInWindow, from: nil)), event) }
    override func rightMouseDown(with event: NSEvent) { onRightMouseDown?(event) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = clock()
        for key in cards.keys.sorted(by: { order($0) < order($1) }) { if let card = cards[key] { drawCard(card, ctx: ctx, t: t) } }
        drawPickers(ctx: ctx, t: t)
        drawPill(ctx: ctx, t: t)
        drawTooltip(ctx: ctx, t: t)
    }

    private func order(_ key: String) -> Int { key == "live" ? 0 : key == "prompt" ? 1 : 2 }

    private func withAlpha(_ alpha: CGFloat, _ ctx: CGContext, _ body: () -> Void) {
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func scaled(_ scale: CGFloat, about c: CGPoint, _ ctx: CGContext, _ body: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -c.x, y: -c.y)
        body()
        ctx.restoreGState()
    }

    static func capsule(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    }

    private func drawPill(ctx: CGContext, t: TimeInterval) {
        let g = pill.value(at: t)
        var opacity = g.opacity
        if let since = reconnectingSince, !reduceMotion { opacity *= FlowBarMotion.reconnectPulse(time: t - since) }
        withAlpha(opacity, ctx) {
            let shape = FlowBarCanvas.capsule(g.rect, radius: g.radius)
            g.fill.color.setFill(); shape.fill()
            if g.borderWidth > 0 {
                let rim = FlowBarCanvas.capsule(g.rect.insetBy(dx: g.borderWidth / 2, dy: g.borderWidth / 2), radius: g.radius - g.borderWidth / 2)
                rim.lineWidth = g.borderWidth
                g.border.color.setStroke(); rim.stroke()
            }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            withAlpha(contentOpacity.value(at: t), ctx) {
                for (kind, anim) in items.sorted(by: { $0.key == .progressFill && $1.key != .progressFill }) {
                    let p = anim.presence.value(at: t)
                    guard p > 0.01 else { continue }
                    let rect = anim.rect.value(at: t)
                    if kind == .progressFill { drawItem(kind, rect: g.rect, t: t); continue }
                    withAlpha(p, ctx) { scaled(p, about: CGPoint(x: rect.midX, y: rect.midY), ctx) { drawItem(kind, rect: rect, t: t) } }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private var waveTint: NSColor { scene.commandMode ? SFMetrics.FlowBar.commandModeBorder : .white }

    private func drawItem(_ kind: FlowBarItemKind, rect: CGRect, t: TimeInterval) {
        switch kind {
        case .mic:
            FlowBarGlyphs.mic(in: rect, color: .white)
        case .waveform:
            let live = scene.isListening && scene.pill != .initializing
            let speaking = live && level.speaking
            let lengths = FlowBarMotion.dictationBars(audioScale: level.audioScale(gain: SFMetrics.Waveform.dictationGain), time: t,
                                                      speaking: speaking, reduceMotion: reduceMotion)
            let color = speaking ? waveTint : waveTint.withAlphaComponent(0.4)
            drawBars(lengths, in: rect, color: color)
        case .meetingWaveform:
            let speaking = level.speaking
            let lengths = FlowBarMotion.meetingBars(audioScale: level.audioScale(gain: SFMetrics.Waveform.meetingGain), time: t,
                                                    speaking: speaking, reduceMotion: reduceMotion)
            let vertical = scene.edge != .bottom
            let content = vertical ? CGRect(x: rect.minX, y: rect.minY + 1.5, width: rect.width, height: 18)
                                   : CGRect(x: rect.minX + 4.5 + 2, y: rect.minY, width: 18, height: rect.height)
            drawBars(lengths, in: content, color: .white, rounded: true)
        case .spinner, .flushSpinner:
            var tint = SFMetrics.Spinner.color.withAlphaComponent(1)
            if scene.commandMode { tint = SFMetrics.FlowBar.commandModeBorder }
            if kind == .flushSpinner { tint = .white }
            let scale: CGFloat = kind == .flushSpinner ? 0.76 : 1
            drawSpinner(center: CGPoint(x: rect.midX, y: rect.midY), scale: scale, tint: tint, t: t)
        case .cancel:
            SFMetrics.FlowBar.cancelButtonFill.setFill(); NSBezierPath(ovalIn: rect).fill()
            FlowBarGlyphs.cross(in: rect.insetBy(dx: 3, dy: 3), color: SFColor.sand50)
        case .finish:
            SFMetrics.FlowBar.finishButtonFill.setFill(); NSBezierPath(ovalIn: rect).fill()
            FlowBarGlyphs.check(in: rect.insetBy(dx: 3, dy: 3), color: SFColor.vast950)
        case .stop:
            SFMetrics.FlowBar.cancelButtonFill.setFill(); NSBezierPath(ovalIn: rect).fill()
            let s = SFMetrics.FlowBar.stopSquareSize
            NSColor.white.setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s),
                         xRadius: SFMetrics.FlowBar.stopSquareRadius, yRadius: SFMetrics.FlowBar.stopSquareRadius).fill()
        case .timer:
            guard let text = FlowBarLayout.timerText(scene) else { return }
            drawLine(NSAttributedString(string: text, attributes: [.font: FlowBarStyle.timer, .foregroundColor: FlowBarStyle.timerText]), in: rect)
        case .label:
            let (main, accent) = FlowBarLayout.labelText(scene)
            let font = FlowBarLayout.labelFont(scene)
            let completed = scene.pill == .transformCompleted || scene.pill == .cleanupCompleted
            let s = NSMutableAttributedString(string: main, attributes: [.font: font, .foregroundColor: completed ? NSColor.white : FlowBarStyle.secondaryText])
            s.append(NSAttributedString(string: accent, attributes: [.font: font, .foregroundColor: completed ? FlowBarStyle.accentText : NSColor.white]))
            drawLine(s, in: rect.insetBy(dx: -2, dy: 0))
        case .sparkle:
            FlowBarGlyphs.sparkle(in: rect, color: .white)
        case .progressFill:
            let fraction: CGFloat
            switch scene.pill {
            case .preparing: fraction = fill.value(at: t)
            case .transformProcessing(_, let started):
                fraction = CGFloat(min(1, max(0, (t - started.timeIntervalSinceReferenceDate) / SFMotion.transformProgressDuration)))
            default: fraction = 0
            }
            FlowBarStyle.progressFill.setFill()
            if scene.edge != .bottom && !FlowBarLayout.staysHorizontal(scene.pill) {
                CGRect(x: rect.minX, y: rect.maxY - rect.height * fraction, width: rect.width, height: rect.height * fraction).fill()
            } else {
                CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height).fill()
            }
        }
    }

    /// Bars centred in their box along the main axis; a bar's ends round as CSS scaling a 0.5-radius 2 × 2 bar does.
    private func drawBars(_ lengths: [CGFloat], in rect: CGRect, color: NSColor, rounded: Bool = false) {
        let vertical = scene.edge != .bottom
        let w = SFMetrics.Waveform.barWidth, gap = SFMetrics.Waveform.barGap
        let total = CGFloat(lengths.count) * w + CGFloat(lengths.count - 1) * gap
        color.setFill()
        for (i, length) in lengths.enumerated() {
            let offset = CGFloat(i) * (w + gap)
            let bar: CGRect
            if vertical {
                bar = CGRect(x: rect.midX - length / 2, y: rect.midY + total / 2 - offset - w, width: length, height: w)
            } else {
                bar = CGRect(x: rect.midX - total / 2 + offset, y: rect.midY - length / 2, width: w, height: length)
            }
            let scale = length / SFMetrics.Waveform.barMinHeight
            let r = SFMetrics.Waveform.barRadius
            let path = rounded ? FlowBarCanvas.capsule(bar, radius: w / 2)
                : NSBezierPath(roundedRect: bar, xRadius: vertical ? min(r * scale, bar.width / 2) : r,
                               yRadius: vertical ? r : min(r * scale, bar.height / 2))
            path.fill()
        }
    }

    private func drawSpinner(center: CGPoint, scale: CGFloat, tint: NSColor, t: TimeInterval) {
        let s = SFMetrics.Spinner.self
        for i in 0..<s.spokes {
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.scale(by: scale)
            transform.rotate(byDegrees: -45 * CGFloat(i))
            let spoke = NSBezierPath(roundedRect: CGRect(x: -s.spokeSize.width / 2, y: s.spokeOffset - s.spokeSize.height / 2,
                                                         width: s.spokeSize.width, height: s.spokeSize.height),
                                     xRadius: s.spokeRadius, yRadius: s.spokeRadius)
            spoke.transform(using: transform as AffineTransform)
            tint.withAlphaComponent(FlowBarMotion.spinnerAlpha(spoke: i, time: reduceMotion ? 0 : t)).setFill()
            spoke.fill()
        }
    }

    private func drawPickers(ctx: CGContext, t: TimeInterval) {
        for (picker, anim) in pickers {
            let p = anim.presence.value(at: t)
            guard p > 0.01 else { continue }
            let rect = anim.rect.value(at: t)
            withAlpha(p, ctx) {
                scaled(p, about: CGPoint(x: rect.midX, y: rect.midY), ctx) {
                    let hovered = scene.hovered == .picker(picker)
                    let w = SFMetrics.FlowBar.pickerBorderWidth
                    (hovered ? SFMetrics.FlowBar.hoverFill : SFMetrics.FlowBar.fill).setFill()
                    NSBezierPath(ovalIn: rect).fill()
                    let rim = NSBezierPath(ovalIn: rect.insetBy(dx: w / 2, dy: w / 2))
                    rim.lineWidth = w
                    (hovered ? SFMetrics.FlowBar.hoverBorder : SFMetrics.FlowBar.border).setStroke(); rim.stroke()
                    let icon = CGRect(x: rect.midX - 7, y: rect.midY - 7, width: 14, height: 14)
                    switch picker {
                    case .hub: FlowBarGlyphs.brandMark(in: icon.insetBy(dx: 0, dy: 1), color: .white)
                    case .quickNote: FlowBarGlyphs.symbol("square.and.pencil", in: icon, color: .white, pointSize: 13)
                    case .sounds:
                        FlowBarGlyphs.symbol(scene.soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill", in: icon, color: .white, pointSize: 13)
                    }
                }
            }
        }
    }

    private func drawTooltip(ctx: CGContext, t: TimeInterval) {
        let alpha = tooltip.opacity.value(at: t)
        guard alpha > 0.01, !tooltip.runs.isEmpty else { return }
        let rect = tooltip.rect.value(at: t)
        withAlpha(alpha, ctx) {
            let shape = FlowBarCanvas.capsule(rect.insetBy(dx: 0.5, dy: 0.5), radius: SFMetrics.FlowBar.tooltipRadius)
            FlowBarStyle.fill.setFill(); shape.fill()
            shape.lineWidth = 1; FlowBarStyle.rim.setStroke(); shape.stroke()
            let s = NSMutableAttributedString()
            for run in tooltip.runs {
                s.append(NSAttributedString(string: run.text, attributes: [.font: run.emphasised ? FlowBarStyle.tooltipBold : FlowBarStyle.tooltip,
                                                                         .foregroundColor: NSColor.white]))
            }
            drawLine(s, in: rect, centred: true)
        }
    }

    // MARK: Cards

    private func drawCard(_ card: CardAnim, ctx: CGContext, t: TimeInterval) {
        let frame = card.layout.frame.offsetBy(dx: 0, dy: card.lift.value(at: t))
        let scale = card.scale.value(at: t)
        withAlpha(card.opacity.value(at: t), ctx) {
            scaled(scale, about: CGPoint(x: frame.midX, y: frame.minY), ctx) {
                let shape = FlowBarCanvas.capsule(frame, radius: card.layout.radius)
                ctx.saveGState()
                switch card.content {
                case .live:
                    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 30, color: NSColor.white.withAlphaComponent(0.2).cgColor)
                    card.layout.fill.setFill(); shape.fill()
                    ctx.setShadow(offset: .zero, blur: 20, color: NSColor.white.withAlphaComponent(0.15).cgColor)
                    shape.fill()
                case .notification(let n, _) where n.variant == .condensed:
                    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 15, color: NSColor(srgbRed: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 0.1).cgColor)
                    card.layout.fill.setFill(); shape.fill()
                default:
                    ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor(srgbRed: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 0.05).cgColor)
                    card.layout.fill.setFill(); shape.fill()
                }
                ctx.restoreGState()
                let layout = FlowBarLayout.offset(card.layout, to: frame)
                switch card.content {
                case .live(let text): drawLiveText(text, layout: layout, shape: shape)
                case .notification(let n, let shownAt): drawNotification(n, shownAt: shownAt, layout: layout, shape: shape, t: t)
                case .prompt(let prompt, let shownAt): drawPrompt(prompt, shownAt: shownAt, layout: layout, shape: shape, t: t)
                }
            }
        }
    }

    private func drawLiveText(_ text: String, layout: FlowBarCardLayout, shape: NSBezierPath) {
        let rim = FlowBarCanvas.capsule(layout.frame.insetBy(dx: 0.5, dy: 0.5), radius: layout.radius - 0.5)
        rim.lineWidth = 1; FlowBarStyle.rim.setStroke(); rim.stroke()
        let inner = layout.frame.insetBy(dx: 20, dy: 20)
        let s = NSAttributedString(string: text, attributes: FlowBarStyle.attributes(FlowBarStyle.liveText, .white, lineHeight: 24, wraps: true))
        let h = s.boundingRect(with: CGSize(width: inner.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: inner).addClip()
        // Auto-scroll: the newest words stay in view at the bottom.
        let top = h > inner.height ? inner.minY + h : inner.maxY
        s.draw(with: CGRect(x: inner.minX, y: top - h, width: inner.width, height: h), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawNotification(_ n: FlowBarNotification, shownAt: Date?, layout: FlowBarCardLayout, shape: NSBezierPath, t: TimeInterval) {
        if let icon = layout.icon {
            switch n.variant {
            case .error: FlowBarGlyphs.symbol("exclamationmark.circle.fill", in: icon, color: SFColor.destructive500, inner: .black, pointSize: 15)
            case .alert: FlowBarGlyphs.symbol("exclamationmark.triangle.fill", in: icon, color: SFColor.warning400, inner: .black, pointSize: 14)
            case .success: FlowBarGlyphs.symbol("checkmark.circle.fill", in: icon, color: SFColor.success500, inner: .black, pointSize: 15)
            default: break
            }
        }
        if let title = layout.title {
            switch n.variant {
            case .mini:
                drawLine(NSAttributedString(string: n.title, attributes: FlowBarStyle.attributes(FlowBarStyle.cardBody, FlowBarStyle.titleText)), in: title)
            case .condensed:
                drawWrapped(n.title, font: FlowBarStyle.cardTitleCondensed, color: FlowBarStyle.titleText, in: title)
            default:
                drawWrapped(n.title, font: FlowBarStyle.cardTitle, color: FlowBarStyle.titleText, in: title)
            }
        }
        if let subtitle = layout.subtitle, let text = n.subtitle {
            drawWrapped(text, font: FlowBarStyle.cardBody, color: FlowBarStyle.secondaryText, in: subtitle)
        }
        for button in layout.buttons { drawButton(button) }
        if let close = layout.close {
            FlowBarGlyphs.cross(in: close.insetBy(dx: 2, dy: 2), color: scene.hovered == .cardClose(id: n.id) ? SFColor.sand50 : SFColor.vast300)
        }
        if let track = layout.progress, let timeout = n.timeout, let shownAt {
            drawCountdown(track: track, fraction: (t - shownAt.timeIntervalSinceReferenceDate) / timeout, shape: shape)
        }
    }

    private func drawPrompt(_ prompt: MeetingPrompt, shownAt: Date?, layout: FlowBarCardLayout, shape: NSBezierPath, t: TimeInterval) {
        if let icon = layout.icon { FlowBarGlyphs.record(in: icon, color: SFMetrics.FlowBar.meetingBorder) }
        if let title = layout.title {
            drawLine(NSAttributedString(string: FlowBarCopy.promptTitle, attributes: FlowBarStyle.attributes(FlowBarStyle.cardTitle, FlowBarStyle.titleText)), in: title)
        }
        if let subtitle = layout.subtitle {
            drawWrapped(FlowBarCopy.promptSubtitle(prompt), font: FlowBarStyle.cardBody, color: FlowBarStyle.secondaryText, in: subtitle)
        }
        for button in layout.buttons { drawButton(button) }
        if let track = layout.progress, let shownAt {
            drawCountdown(track: track, fraction: (t - shownAt.timeIntervalSinceReferenceDate) / max(prompt.timeout, 0.1), shape: shape)
        }
    }

    /// The 3 pt bar along the card's bottom: lumen on the tertiary track, filling as the time runs out (§2.12).
    private func drawCountdown(track: CGRect, fraction: Double, shape: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        SFColor.vast600.setFill(); track.fill()
        SFColor.lumen.setFill()
        CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(min(max(fraction, 0), 1)), height: track.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawButton(_ b: FlowBarCardLayout.Button) {
        let hovered = scene.hovered == b.element
        var text = FlowBarStyle.titleText
        var font = FlowBarStyle.button
        switch b.style {
        case .ghost:
            if b.element == .prompt(.neverForApp) {
                text = hovered ? SFColor.sand50 : FlowBarStyle.secondaryText; font = FlowBarStyle.cardBody
            } else {
                text = hovered ? SFColor.sand50.withAlphaComponent(0.8) : .white
            }
        case .softDark:
            (hovered ? SFColor.vast700 : FlowBarStyle.softDark).setFill()
            NSBezierPath(roundedRect: b.rect, xRadius: 8, yRadius: 8).fill()
        case .softDarkVast:
            (hovered ? SFColor.vast800 : FlowBarStyle.softDarkVast).setFill()
            NSBezierPath(roundedRect: b.rect, xRadius: 8, yRadius: 8).fill()
            text = SFColor.sand600
        case .primary:
            (hovered ? NSColor(hex: "#f7f7db") : FlowBarStyle.primaryButton).setFill()
            NSBezierPath(roundedRect: b.rect, xRadius: 8, yRadius: 8).fill()
            text = SFColor.vast950
        case .condensed:
            NSColor.white.withAlphaComponent(hovered ? 0.12 : 0.08).setFill()
            NSBezierPath(roundedRect: b.rect, xRadius: 8, yRadius: 8).fill()
            font = FlowBarStyle.cardBody
        }
        drawLine(NSAttributedString(string: b.title, attributes: FlowBarStyle.attributes(font, text)), in: b.rect, centred: b.style != .ghost)
    }

    // MARK: Text

    /// One line, vertically centred on the rect (CSS centres glyphs in the line box).
    private func drawLine(_ s: NSAttributedString, in rect: CGRect, centred: Bool = false) {
        guard s.length > 0 else { return }
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? FlowBarStyle.cardBody
        let h = ceil(font.ascender - font.descender)
        let w = ceil(s.size().width)
        let x = centred ? rect.midX - w / 2 : rect.minX
        let width = centred ? w : rect.width
        let line = NSMutableAttributedString(attributedString: s)
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        line.draw(with: CGRect(x: x, y: rect.midY - h / 2, width: width + 1, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Wrapped text at a 20 pt line height, glyphs centred in each line as CSS does.
    private func drawWrapped(_ text: String, font: NSFont, color: NSColor, in rect: CGRect) {
        var attributes = FlowBarStyle.attributes(font, color, lineHeight: FlowBarStyle.lineHeight, wraps: true)
        attributes[.baselineOffset] = (FlowBarStyle.lineHeight - (font.ascender - font.descender)) / 2 - 0.5
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
        style?.lineBreakMode = .byWordWrapping
        attributes[.paragraphStyle] = style
        NSAttributedString(string: text, attributes: attributes)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

extension FlowBarCanvas {
    /// Pins the level for renders and tests: settled at `value`, speaking when loud enough.
    func pinLevel(_ value: Double) {
        level = LevelSmoother(settledAt: value)
    }
}

/// A clickable part of the bar as VoiceOver sees it.
final class FlowBarAccessibilityElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        press?()
        return press != nil
    }
}

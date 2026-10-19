import AppKit
import SuperFlowCore

/// The bar's glyphs, drawn as paths at the spec's sizes (ui-reference.md §2.4, §2.5, §2.11, §9.1, §10.2) so they stay
/// crisp at every scale and render the same offscreen. Rects are in a non-flipped view.
enum FlowBarGlyphs {
    /// Microphone, 12 × 16: a filled capsule over a U-shaped stand and a stem.
    static func mic(in r: CGRect, color: NSColor) {
        color.set()
        let s = r.width / 12
        NSBezierPath(roundedRect: CGRect(x: r.minX + 3.25 * s, y: r.minY + 6 * s, width: 5.5 * s, height: 10 * s),
                     xRadius: 2.75 * s, yRadius: 2.75 * s).fill()
        let stand = NSBezierPath()
        stand.lineWidth = 1.5 * s
        stand.lineCapStyle = .round
        stand.appendArc(withCenter: CGPoint(x: r.midX, y: r.minY + 9.5 * s), radius: 4.75 * s, startAngle: 180, endAngle: 360)
        stand.move(to: CGPoint(x: r.midX, y: r.minY + 4.75 * s))
        stand.line(to: CGPoint(x: r.midX, y: r.minY + 0.75 * s))
        stand.stroke()
    }

    /// "x", 12 pt with the 24-unit stroke of 3 (1.5 pt).
    static func cross(in r: CGRect, color: NSColor, lineWidth: CGFloat = 1.5) {
        let path = NSBezierPath()
        let i = r.width / 4
        path.move(to: CGPoint(x: r.minX + i, y: r.minY + i)); path.line(to: CGPoint(x: r.maxX - i, y: r.maxY - i))
        path.move(to: CGPoint(x: r.minX + i, y: r.maxY - i)); path.line(to: CGPoint(x: r.maxX - i, y: r.minY + i))
        path.lineWidth = lineWidth; path.lineCapStyle = .round
        color.set(); path.stroke()
    }

    /// "check", 12 pt, stroke 1.5.
    static func check(in r: CGRect, color: NSColor) {
        let s = r.width / 12
        let path = NSBezierPath()
        path.move(to: CGPoint(x: r.minX + 10 * s, y: r.minY + 9 * s))
        path.line(to: CGPoint(x: r.minX + 4.5 * s, y: r.minY + 3.5 * s))
        path.line(to: CGPoint(x: r.minX + 2 * s, y: r.minY + 6 * s))
        path.lineWidth = 1.5 * s; path.lineCapStyle = .round; path.lineJoinStyle = .round
        color.set(); path.stroke()
    }

    /// Record: a ring around a filled dot (the meeting-detected prompt's icon, §10.2).
    static func record(in r: CGRect, color: NSColor) {
        color.set()
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
        ring.lineWidth = 1.5; ring.stroke()
        NSBezierPath(ovalIn: r.insetBy(dx: r.width * 0.3, dy: r.height * 0.3)).fill()
    }

    /// Four-point sparkle (Transform done, §2.11).
    static func sparkle(in r: CGRect, color: NSColor) {
        let c = CGPoint(x: r.midX, y: r.midY), R = r.width / 2, k = R * 0.18
        let path = NSBezierPath()
        path.move(to: CGPoint(x: c.x, y: c.y + R))
        path.curve(to: CGPoint(x: c.x + R, y: c.y), controlPoint1: CGPoint(x: c.x + k, y: c.y + k), controlPoint2: CGPoint(x: c.x + k, y: c.y + k))
        path.curve(to: CGPoint(x: c.x, y: c.y - R), controlPoint1: CGPoint(x: c.x + k, y: c.y - k), controlPoint2: CGPoint(x: c.x + k, y: c.y - k))
        path.curve(to: CGPoint(x: c.x - R, y: c.y), controlPoint1: CGPoint(x: c.x - k, y: c.y - k), controlPoint2: CGPoint(x: c.x - k, y: c.y - k))
        path.curve(to: CGPoint(x: c.x, y: c.y + R), controlPoint1: CGPoint(x: c.x - k, y: c.y + k), controlPoint2: CGPoint(x: c.x - k, y: c.y + k))
        path.close()
        color.set(); path.fill()
    }

    /// Super Flow's mark: five rounded bars, tall in the middle (the app icon in silhouette), for "Open Super Flow".
    static func brandMark(in r: CGRect, color: NSColor) {
        let heights: [CGFloat] = [0.52, 0.79, 1, 0.79, 0.52]
        let bar: CGFloat = 1.75, gap: CGFloat = 1.25
        var x = r.midX - (5 * bar + 4 * gap) / 2
        color.set()
        for h in heights {
            let height = r.height * h
            NSBezierPath(roundedRect: CGRect(x: x, y: r.midY - height / 2, width: bar, height: height), xRadius: bar / 2, yRadius: bar / 2).fill()
            x += bar + gap
        }
    }

    /// An SF Symbol tinted and fitted into a rect; `inner` colours a filled symbol's mark (the "!" in a filled circle).
    static func symbol(_ name: String, in r: CGRect, color: NSColor, inner: NSColor? = nil, pointSize: CGFloat,
                       weight: NSFont.Weight = .medium) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: inner.map { [$0, color] } ?? [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let size = image.size
        let scale = min(r.width / size.width, r.height / size.height, 1)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: CGRect(x: r.midX - fitted.width / 2, y: r.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
    }
}

import AppKit
import SuperFlowCore

/// Offscreen renders of the bar (`cacheDisplay` into a 2× bitmap, never a window on screen): the catalogue of every
/// state, used by the self-test to check pixels and by reviewers to compare against ui-reference.md.
@MainActor
public enum FlowBarSnapshot {
    public enum Backdrop: String, CaseIterable, Sendable {
        case light, dark
        var color: NSColor { self == .light ? NSColor(hex: "#E9E8E1") : NSColor(hex: "#1E1E1E") }
    }

    /// One state to render: the scene, the microphone level, and the clock (seconds after the scene's start).
    public struct Case {
        public var name: String
        public var scene: FlowBarScene
        public var level: Double
        public var time: TimeInterval
    }

    /// The clock origin the catalogue's scenes are built from.
    public static let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Renders a scene at 2× and composites it on the backdrop, cropped to what is drawn (or the whole window).
    public static func render(_ scene: FlowBarScene, level: Double = 0, time: TimeInterval = 0, backdrop: Backdrop,
                              cropped: Bool = true) -> NSBitmapImageRep {
        let size = scene.edge == .bottom ? SFMetrics.FlowBar.bottomWindowSize : NSSize(width: SFMetrics.FlowBar.sideWindowWidth, height: 700)
        let canvas = FlowBarCanvas(frame: CGRect(origin: .zero, size: size))
        canvas.clock = { origin.timeIntervalSinceReferenceDate + time }
        canvas.pinLevel(level)
        canvas.apply(scene, animated: false)

        let full = bitmap(size)
        canvas.cacheDisplay(in: canvas.bounds, to: full)

        let crop = cropped ? cropRect(canvas.frames, edge: scene.edge, bounds: canvas.bounds) : canvas.bounds
        let out = bitmap(crop.size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        backdrop.color.setFill()
        CGRect(origin: .zero, size: crop.size).fill()
        full.draw(in: CGRect(x: -crop.minX, y: -crop.minY, width: size.width, height: size.height),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    /// Where each scene's pill sits inside a render, in render points (for pixel checks).
    public static func pillRect(_ scene: FlowBarScene) -> CGRect {
        let size = scene.edge == .bottom ? SFMetrics.FlowBar.bottomWindowSize : NSSize(width: SFMetrics.FlowBar.sideWindowWidth, height: 700)
        let bounds = CGRect(origin: .zero, size: size)
        let frames = FlowBarLayout.frames(for: scene, in: bounds)
        let crop = cropRect(frames, edge: scene.edge, bounds: bounds)
        return frames.pill.offsetBy(dx: -crop.minX, dy: -crop.minY)
    }

    /// The pill's frame `seconds` into the animated change from one scene to the next (bottom-edge window points).
    public static func pillFrame(from a: FlowBarScene, to b: FlowBarScene, after seconds: TimeInterval) -> CGRect {
        let canvas = FlowBarCanvas(frame: CGRect(origin: .zero, size: SFMetrics.FlowBar.bottomWindowSize))
        var t: TimeInterval = 0
        canvas.clock = { t }
        canvas.apply(a, animated: false)
        canvas.apply(b, animated: true)
        t = seconds
        return canvas.currentPillFrame
    }

    static func bitmap(_ size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        return rep
    }

    /// The drawn content plus a margin; on the bottom edge it keeps the screen's bottom edge in frame.
    static func cropRect(_ f: FlowBarFrames, edge: FlowBarEdge, bounds: CGRect) -> CGRect {
        var content = f.pill
        for r in f.pickers.values { content = content.union(r) }
        for card in [f.liveText, f.prompt, f.notification].compactMap({ $0 }) { content = content.union(card.frame) }
        if let tip = f.tooltip { content = content.union(tip) }
        content = content.insetBy(dx: -28, dy: -28)
        let minWidth: CGFloat = 260
        if content.width < minWidth { content = content.insetBy(dx: -(minWidth - content.width) / 2, dy: 0) }
        switch edge {
        case .bottom: content = CGRect(x: content.minX, y: bounds.minY, width: content.width, height: content.maxY - bounds.minY)
        case .left: content = CGRect(x: bounds.minX, y: content.minY, width: content.maxX - bounds.minX, height: content.height)
        case .right: content = CGRect(x: content.minX, y: content.minY, width: bounds.maxX - content.minX, height: content.height)
        }
        return content.intersection(bounds).integral
    }

    /// Writes every case on both backdrops as PNGs; returns the files.
    @discardableResult public static func writeCatalogue(to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        for item in catalogue() {
            for backdrop in Backdrop.allCases {
                let rep = render(item.scene, level: item.level, time: item.time, backdrop: backdrop)
                let url = folder.appendingPathComponent("\(item.name)-\(backdrop.rawValue).png")
                try rep.representation(using: .png, properties: [:])?.write(to: url)
                files.append(url)
            }
        }
        return files
    }

    // MARK: Catalogue

    /// Every state the bar can show, built through `FlowBarModel` the way the app drives it.
    public static func catalogue() -> [Case] {
        var cases: [Case] = []
        func add(_ name: String, level: Double = 0, after seconds: TimeInterval = 0.4, edge: FlowBarEdge = .bottom,
                 _ build: (inout FlowBarModel) -> Void) {
            var model = FlowBarModel()
            model.edge = edge
            build(&model)
            cases.append(Case(name: name, scene: model.scene(at: origin.addingTimeInterval(seconds)), level: level, time: seconds))
        }
        let t0 = origin

        add("01-resting") { $0.setState(.resting, now: t0) }
        add("02-ready-hover") { $0.setState(.resting, now: t0); $0.pointerInside = true; $0.hovered = .pill }
        add("03-ready-quick-note") { $0.setState(.resting, now: t0); $0.pointerInside = true; $0.hovered = .picker(.quickNote) }
        add("04-ready-sounds-off") { $0.setState(.resting, now: t0); $0.pointerInside = true; $0.soundsOn = false; $0.hovered = .picker(.sounds) }
        add("05-ready-hub") { $0.setState(.resting, now: t0); $0.pointerInside = true; $0.hovered = .picker(.hub) }
        add("06-initializing") { $0.setState(.initializing, now: t0) }
        add("07-push-to-talk-silent") { $0.setState(.listening(mode: .pushToTalk), now: t0) }
        add("08-push-to-talk-speaking", level: 0.9, after: 2.3) { $0.setState(.listening(mode: .pushToTalk), now: t0) }
        add("09-hands-free", level: 0.7, after: 42.4) { $0.setState(.listening(mode: .handsFree), now: t0) }
        add("10-hands-free-finish-tooltip", level: 0.3, after: 65.2) {
            $0.setState(.listening(mode: .handsFree), now: t0); $0.pointerInside = true; $0.hovered = .finish
        }
        add("11-hands-free-live-text", level: 0.5, after: 12.6) {
            $0.setState(.listening(mode: .handsFree), now: t0)
            $0.liveText = "Hey Priya, quick update on the launch plan. The beta goes out Thursday, and I'd like the release notes " +
                "drafted by Wednesday so we have a day to review them together. Can you also check whether"
        }
        add("12-processing", after: 0.5) { $0.setState(.listening(mode: .pushToTalk), now: t0); $0.setState(.processing, now: t0) }
        add("13-command-listening", level: 0.8, after: 1.4) { $0.setState(.listening(mode: .command), now: t0) }
        add("14-command-processing", after: 0.3) { $0.setState(.listening(mode: .command), now: t0); $0.setState(.processing, now: t0) }
        add("15-getting-ready") { $0.setState(.preparing(fraction: 0.42), now: t0); $0.pointerInside = true; $0.hovered = .pill }
        add("16-transform-processing", after: 3.1) { $0.setState(.transformProcessing(label: "Polishing"), now: t0) }
        add("17-transform-done") { $0.setState(.transformCompleted, now: t0) }
        add("18-cleanup-done") { $0.setState(.cleanupCompleted, now: t0) }
        add("19-error-with-fix", after: 0.6) {
            $0.setState(.error, now: t0)
            $0.show(FlowBarNotification(id: "mic-permission", title: "Microphone access is off",
                                        subtitle: "Super Flow needs the microphone to hear you. Turn it on in System Settings › Privacy & Security › Microphone.",
                                        variant: .error, timeout: nil, actions: ["Open System Settings"]), now: t0)
        }
        add("20-meeting-detected", after: 9) {
            $0.setState(.resting, now: t0)
            $0.showPrompt(MeetingPrompt(title: "Design review", platform: .zoom), now: t0)
        }
        add("21-meeting-detected-browser", after: 21) {
            $0.setState(.resting, now: t0)
            $0.showPrompt(MeetingPrompt(title: "", platform: .googleMeet), now: t0)
        }
        add("22-meeting-starting") { $0.setState(.meeting(.pending), now: t0) }
        add("23-meeting-recording", level: 0.9, after: 754.2) { $0.setState(.meeting(.recording(wordCount: 1_284, startedAt: t0)), now: t0) }
        add("24-meeting-recording-words", level: 0.2, after: 754.2) {
            $0.setState(.meeting(.recording(wordCount: 1_284, startedAt: t0)), now: t0); $0.pointerInside = true; $0.hovered = .meetingBody
        }
        add("25-meeting-stop-tooltip", after: 3_725) {
            $0.setState(.meeting(.recording(wordCount: 9_120, startedAt: t0)), now: t0); $0.pointerInside = true; $0.hovered = .meetingStop
        }
        add("26-meeting-reconnecting", after: 301) {
            $0.setState(.meeting(.recording(wordCount: 410, startedAt: t0)), now: t0); $0.setState(.meeting(.reconnecting), now: t0)
        }
        add("27-meeting-wrapping-up", after: 1_801) {
            $0.setState(.meeting(.recording(wordCount: 410, startedAt: t0)), now: t0); $0.setState(.meeting(.stopping), now: t0)
        }
        add("28-meeting-under-dictation", level: 0.4, after: 1.2) {
            $0.setState(.meeting(.recording(wordCount: 410, startedAt: t0)), now: t0); $0.setState(.listening(mode: .handsFree), now: t0)
        }
        add("29-notification-mini") {
            $0.setState(.resting, now: t0)
            $0.show(FlowBarNotification(id: "hidden", title: FlowBarCopy.hiddenForHour, actions: [FlowBarCopy.undo]), now: t0)
        }
        add("30-notification-condensed", after: 4) {
            $0.setState(.resting, now: t0)
            $0.show(FlowBarNotification(id: "paste", title: "Couldn’t paste here. The text is on your clipboard.", variant: .condensed,
                                        timeout: 10, actions: ["Paste again"]), now: t0)
        }
        add("31-notification-alert") {
            $0.setState(.resting, now: t0)
            $0.show(FlowBarNotification(id: "no-audio", title: "We’re not hearing anything",
                                        subtitle: "Check that MacBook Pro Microphone isn’t muted, or pick another one.",
                                        variant: .alert, timeout: nil, actions: ["Microphone settings", "Ignore"]), now: t0)
        }
        add("32-notification-success") {
            $0.setState(.resting, now: t0)
            $0.show(FlowBarNotification(id: "summary", title: "Your notes are ready", subtitle: "Design review · 42 min, 6 action items",
                                        variant: .success, timeout: 15, actions: ["Open notes"]), now: t0)
        }
        add("33-left-ready", edge: .left) { $0.setState(.resting, now: t0); $0.pointerInside = true; $0.hovered = .pill }
        add("34-left-hands-free", level: 0.7, after: 8.2, edge: .left) { $0.setState(.listening(mode: .handsFree), now: t0) }
        add("35-right-meeting", level: 0.9, after: 95, edge: .right) { $0.setState(.meeting(.recording(wordCount: 220, startedAt: t0)), now: t0) }
        add("36-right-processing", edge: .right) { $0.setState(.processing, now: t0) }
        return cases
    }
}

import AppKit
import SuperFlowCore

/// What the bar needs to know about the screen it follows (ui-reference.md §2.2), in Cocoa screen coordinates.
public struct FlowBarScreen: Equatable, Sendable {
    public var frame: CGRect
    /// `NSScreen.visibleFrame`: below the menu bar and clear of the Dock while the Dock keeps its space.
    public var visibleFrame: CGRect
    /// The screen shows a full-screen space (one app, or two side by side): no Dock there.
    public var fullScreenSpace: Bool

    public init(frame: CGRect, visibleFrame: CGRect, fullScreenSpace: Bool = false) {
        self.frame = frame; self.visibleFrame = visibleFrame; self.fullScreenSpace = fullScreenSpace
    }
}

/// Where the bar's window goes (ui-reference.md §2.2). Pure: the rules the self-test checks; `FlowBar` feeds them
/// from `NSScreen` and the window list.
///
/// The rule is the original's (module 58601 and its helper's Dock observer): the window's bottom edge sits on the
/// bottom of the usable area — `visibleFrame` while the Dock shows on that screen, so the pill clears the Dock at any
/// size; with no Dock there (a full-screen space, or the Dock set to hide) the Dock's strip is added back and the bar
/// drops to the screen's bottom edge. The menu bar's inset always stays.
public enum FlowBarPlacement {
    /// An inset on the Dock's side at most this thick is the hidden Dock's trigger strip, not a Dock.
    static let hiddenDockStrip: CGFloat = 8
    /// Moves shorter than this on both axes animate; longer ones (another display) jump, like the original's
    /// 400 ms `monitorMove`.
    static let animatedMoveLimit: CGFloat = 100
    /// Rounding slack when comparing window bounds with screen edges.
    static let edgeSlack: CGFloat = 1

    /// The area the bar's window is placed in.
    public static func usableArea(_ screen: FlowBarScreen) -> CGRect {
        let f = screen.frame, v = screen.visibleFrame
        let dockInset = max(v.minY - f.minY, v.minX - f.minX, f.maxX - v.maxX, 0)
        if !screen.fullScreenSpace && dockInset > hiddenDockStrip { return v }
        return CGRect(x: f.minX, y: f.minY, width: f.width, height: max(0, v.maxY - f.minY))
    }

    /// The window's frame on a screen for a dock edge.
    public static func windowFrame(edge: FlowBarEdge, on screen: FlowBarScreen) -> CGRect {
        FlowBarLayout.windowFrame(edge: edge, usableArea: usableArea(screen))
    }

    /// Whether ordinary windows (Cocoa coordinates) fill a screen the way a full-screen space does: each from the
    /// screen's bottom edge up to the menu bar's line, together from its left edge to its right. A zoomed window
    /// stops at the Dock, so it never counts while the Dock shows; a full-screen window below the camera housing
    /// still reaches the menu bar's line.
    public static func isFullScreenSpace(windows: [CGRect], frame: CGRect, visibleFrame: CGRect) -> Bool {
        let tall = windows.map { $0.intersection(frame) }.filter {
            !$0.isNull && $0.width > edgeSlack && $0.minY <= frame.minY + edgeSlack && $0.maxY >= visibleFrame.maxY - edgeSlack
        }
        guard let minX = tall.map(\.minX).min(), let maxX = tall.map(\.maxX).max() else { return false }
        return minX <= frame.minX + edgeSlack && maxX >= frame.maxX - edgeSlack
    }

    /// Whether a move from one frame to the next animates (same display, a Dock's height or so) or jumps.
    public static func animatesMove(from old: CGRect, to new: CGRect) -> Bool {
        old.size == new.size && abs(old.minX - new.minX) < animatedMoveLimit && abs(old.minY - new.minY) < animatedMoveLimit
    }
}

extension FlowBarScreen {
    /// The screen as it is now. Reads only window bounds and layers from the window list (no names, no pixels, no
    /// Screen Recording permission).
    @MainActor static func current(_ screen: NSScreen) -> FlowBarScreen {
        FlowBarScreen(frame: screen.frame, visibleFrame: screen.visibleFrame,
                      fullScreenSpace: FlowBarPlacement.isFullScreenSpace(windows: ordinaryWindowBounds(), frame: screen.frame,
                                                                          visibleFrame: screen.visibleFrame))
    }

    /// On-screen windows at the normal level (the Dock, menus and the bar itself sit above it), in Cocoa coordinates.
    @MainActor private static func ordinaryWindowBounds() -> [CGRect] {
        guard let primary = NSScreen.screens.first?.frame,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String], CFGetTypeID(dict as CFTypeRef) == CFDictionaryGetTypeID(),
                  let r = CGRect(dictionaryRepresentation: dict as! CFDictionary) else { return nil }
            // The window list counts from the primary display's top-left corner; Cocoa from its bottom-left.
            return CGRect(x: r.minX, y: primary.maxY - r.maxY, width: r.width, height: r.height)
        }
    }
}

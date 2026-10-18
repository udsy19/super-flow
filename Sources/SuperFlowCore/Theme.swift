import AppKit
import QuartzCore

// Design tokens from docs/specs/ui-reference.md, shared so every module draws with the same numbers. Section numbers
// below refer to ui-reference.md.

public extension NSColor {
    /// "#RRGGBB" or "#RRGGBBAA" (the "#" is optional); malformed input gives magenta so it shows.
    convenience init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else {
            self.init(srgbRed: 1, green: 0, blue: 1, alpha: 1); return
        }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255, green: CGFloat((rgba >> 16) & 0xFF) / 255,
                  blue: CGFloat((rgba >> 8) & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }

    /// "#RRGGBB" in sRGB (alpha dropped).
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

// MARK: - Colours (§1.1, §1.2)

/// Raw palette and semantic tokens. The hub follows `Defaults[.theme]`; the Flow Bar always uses the light values
/// (it stays black whatever the appearance, §1.2).
public enum SFColor {
    // Raw scales used by the semantic tokens (§1.1).
    public static let sand50 = NSColor(hex: "#fcfcfb"), sand500 = NSColor(hex: "#f5f4f0"), sand600 = NSColor(hex: "#eeebe3")
    public static let sand950 = NSColor(hex: "#4d4a42")
    public static let vast50 = NSColor(hex: "#e9e8e1"), vast100 = NSColor(hex: "#deddd7"), vast300 = NSColor(hex: "#b3b2ad")
    public static let vast400 = NSColor(hex: "#9d9c98"), vast500 = NSColor(hex: "#878683"), vast600 = NSColor(hex: "#71716e")
    public static let vast700 = NSColor(hex: "#5b5b59"), vast800 = NSColor(hex: "#464544"), vast900 = NSColor(hex: "#30302f")
    public static let vast925 = NSColor(hex: "#202020"), vast950 = NSColor(hex: "#1a1a1a")
    public static let dawn500 = NSColor(hex: "#f0d7ff"), dawn600 = NSColor(hex: "#d2ace9")
    public static let signal500 = NSColor(hex: "#ffbcf2")
    public static let lumen = NSColor(hex: "#ffffeb")
    public static let glow300 = NSColor(hex: "#ffa946"), glow500 = NSColor(hex: "#af6a06")
    public static let flare400 = NSColor(hex: "#ff6c4c")
    public static let chord600 = NSColor(hex: "#7232a6")
    public static let fathom500 = NSColor(hex: "#68bdb0")
    public static let green50 = NSColor(hex: "#ecfdf5"), green400 = NSColor(hex: "#34d399"), green500 = NSColor(hex: "#10b981")
    public static let green600 = NSColor(hex: "#059669"), green700 = NSColor(hex: "#047857")
    public static let red450 = NSColor(hex: "#ff5757"), red600 = NSColor(hex: "#dc2626")
    public static let destructive500 = NSColor(hex: "#ee6a6a")
    public static let warning400 = NSColor(hex: "#ffd467")
    public static let success500 = NSColor(hex: "#4fbf78")
    public static let white = NSColor.white, black = NSColor.black

    /// A named colour that resolves per appearance.
    public static func dynamic(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("superflow." + name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // Semantic tokens (§1.2).
    public static let background = dynamic("background", light: sand50, dark: vast950)
    public static let backgroundSecondary = dynamic("backgroundSecondary", light: sand600, dark: vast900)
    public static let backgroundTertiary = dynamic("backgroundTertiary", light: sand500, dark: vast925)
    public static let card = dynamic("card", light: white, dark: black)
    public static let primary = dynamic("primary", light: vast950, dark: sand50)
    public static let primaryForeground = dynamic("primaryForeground", light: sand50, dark: vast950)
    public static let foreground = dynamic("foreground", light: vast950, dark: vast50)
    public static let foregroundSecondary = dynamic("foregroundSecondary", light: vast950, dark: vast100)
    public static let foregroundTertiary = dynamic("foregroundTertiary", light: vast600, dark: vast400)
    public static let border = dynamic("border", light: sand600, dark: vast900)
    public static let ring = dynamic("ring", light: sand950, dark: sand600)
    public static let destructive = dynamic("destructive", light: red600, dark: red450)
    public static let success = dynamic("success", light: green600, dark: green400)
    public static let recording = dynamic("recording", light: green600, dark: green400)
    public static let mutedHover = NSColor(hex: "#f1ebe1")

    /// Rainbow accent ring (§1.9).
    public static let rainbowRing: [NSColor] = [dawn500, signal500, flare400, glow300, chord600, dawn500]
    public static let rainbowLabel: [NSColor] = [NSColor(hex: "#FFD5A4"), NSColor(hex: "#FFAB9A"), NSColor(hex: "#FFC1F4"), NSColor(hex: "#DBA0FF")]
}

// MARK: - Type (§1.3)

/// Figtree is the reference app's face; the rebuild uses the system font at the same sizes and weights.
public enum SFFont {
    public enum TextSize: CaseIterable { case lg, md, sm, xs, xxs }

    public static func size(_ size: TextSize) -> (points: CGFloat, lineHeight: CGFloat) {
        switch size {
        case .lg: (18, 28)
        case .md: (16, 24)
        case .sm: (15, 20)
        case .xs: (12, 20)
        case .xxs: (10, 18)
        }
    }

    /// regular 400 / emphasis 550 / strong 600.
    public static let emphasisWeight = NSFont.Weight(rawValue: 0.23)

    public static func text(_ size: TextSize = .sm, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: SFFont.size(size).points, weight: weight)
    }

    /// Sans headings, weight 600: 32/40, 28/34, 24/32, 20/28, 18/24.
    public static func heading(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [32, 28, 24, 20, 18]
        return .systemFont(ofSize: sizes[min(max(level, 1), 5) - 1], weight: .semibold)
    }

    /// Serif display headings (EB Garamond in the reference): 72, 48, 36, 28, tracking −0.04em.
    public static func display(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [72, 48, 36, 28]
        let size = sizes[min(max(level, 1), 4) - 1]
        return NSFont(descriptor: NSFontDescriptor.preferredFontDescriptor(forTextStyle: .title1).withDesign(.serif) ?? NSFontDescriptor(),
                      size: size) ?? .systemFont(ofSize: size)
    }

    public static let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
    /// Section labels: 12/20 600 uppercase, tracking .075em.
    public static let sectionLabel = NSFont.systemFont(ofSize: 12, weight: .semibold)
    public static let sectionLabelTracking: CGFloat = 0.075 * 12
}

// MARK: - Metrics

public enum SFMetrics {
    /// Spacing scale (§1.4).
    public static let spacing: [CGFloat] = [0, 2, 4, 8, 12, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112]

    /// Corner radii in use (§1.5).
    public enum Radius {
        public static let xs: CGFloat = 4, sm: CGFloat = 6, md: CGFloat = 8, lg: CGFloat = 12, xl: CGFloat = 16, xxl: CGFloat = 24
        public static let pill: CGFloat = 9999
        public static let flowBar: CGFloat = 22.5
    }

    /// Shadows as ink `rgba(26,26,26,alpha)` layers (§1.6).
    public struct Shadow: Equatable, Sendable {
        public var offset: CGSize
        public var blur: CGFloat
        public var alpha: CGFloat
        public init(offset: CGSize, blur: CGFloat, alpha: CGFloat) { self.offset = offset; self.blur = blur; self.alpha = alpha }

        public static let xs = Shadow(offset: CGSize(width: 0, height: -1), blur: 2, alpha: 0.05)
        public static let lg = Shadow(offset: CGSize(width: 0, height: -10), blur: 15, alpha: 0.10)
        public static let xl = Shadow(offset: CGSize(width: 0, height: -20), blur: 25, alpha: 0.10)
    }

    /// The Flow Bar (§2).
    public enum FlowBar {
        /// Transparent canvas sizes per edge (§2.2).
        public static let bottomWindowSize = NSSize(width: 512, height: 614)
        public static let sideWindowWidth: CGFloat = 490
        public static let sideWindowMaxHeight: CGFloat = 1144
        /// The pill's bottom edge sits this far above the usable area; on a side edge it sits this far in.
        public static let bottomInset: CGFloat = 14
        public static let sideInset: CGFloat = 6
        /// The display under the cursor is re-read this often.
        public static let followCursorInterval: TimeInterval = 0.4
        public static let windowLevel = NSWindow.Level.screenSaver

        public static let fill = NSColor.black
        public static let border = SFColor.vast900
        public static let hoverFill = SFColor.vast900
        public static let hoverBorder = SFColor.vast700
        public static let borderWidth: CGFloat = 1
        public static let radius: CGFloat = Radius.flowBar
        public static let height: CGFloat = 30

        /// Pill sizes per state on the bottom edge; transposed on the side edges (§2.4).
        public static let restingSize = NSSize(width: 40, height: 8)
        public static let restingRadius: CGFloat = 6
        public static let restingFill = NSColor.black.withAlphaComponent(0.5)
        public static let restingBorder = NSColor.white.withAlphaComponent(0.5)
        public static let readySize = NSSize(width: 50, height: 30)
        public static let pushToTalkSize = NSSize(width: 73, height: 30)
        public static let handsFreeSize = NSSize(width: 102.5, height: 30)
        public static let processingSize = NSSize(width: 98, height: 30)
        public static let transformProcessingSize = NSSize(width: 136, height: 30)
        public static let transformCompletedSize = NSSize(width: 152, height: 30)
        public static let errorSize = NSSize(width: 91, height: 30)
        public static let errorBorderWidth: CGFloat = 1.5
        public static let errorBorder = SFColor.destructive500
        public static let reminderHeight: CGFloat = 32
        /// The hit target grows this much on every side in the ready state (§2.3).
        public static let readyHitInset: CGFloat = 12
        public static let micGlyphSize = NSSize(width: 12, height: 16)

        /// Command Mode overlay (§2.4): 1 pt amber border and bars; meeting: 2 pt green.
        public static let commandModeBorder = SFColor.glow300
        public static let meetingBorder = SFColor.green500
        public static let meetingBorderWidth: CGFloat = 2
        public static let meetingReconnectingBorder = SFColor.green700
        public static let meetingPendingBorder = SFColor.vast700

        /// Hands-free buttons (§2.5): 18 pt circles.
        public static let handsFreeButtonSize: CGFloat = 18
        public static let cancelButtonFill = SFColor.sand950
        public static let finishButtonFill = SFColor.sand50
        public static let handsFreeRowGap: CGFloat = 4
        public static let processingRowGap: CGFloat = 6

        /// Meeting stop button (§10.2).
        public static let stopButtonSize: CGFloat = 19
        public static let stopSquareSize: CGFloat = 7.5
        public static let stopSquareRadius: CGFloat = 2
        public static let meetingRowGap: CGFloat = 12

        /// Pickers beside the pill (§2.9).
        public static let pickerSize: CGFloat = 30
        public static let pickerBorderWidth: CGFloat = 1.5
        public static let pickerIconSize: CGFloat = 14
        public static let pickerGap: CGFloat = 2

        /// Tooltips (§2.10).
        public static let tooltipRadius: CGFloat = 34
        public static let tooltipPadding = NSSize(width: 14, height: 6)
        public static let tooltipOffset: CGFloat = 4
        public static let tooltipShowDelay: TimeInterval = 0.05

        /// Notification cards (§2.12).
        public static let notificationMaxSize = NSSize(width: 440, height: 294)
        public static let notificationRadius: CGFloat = 24
        public static let notificationMiniRadius: CGFloat = 20
        public static let notificationPadding: CGFloat = 12
        public static let notificationOffset: CGFloat = 32
        public static let notificationProgressHeight: CGFloat = 3

        /// Live streaming text panel (§2.13).
        public static let liveTextSize = NSSize(width: 400, height: 200)
        public static let liveTextRadius: CGFloat = 11
        public static let liveTextOffset: CGFloat = 40

        /// Drag to move (§2.14).
        public static let dropZoneBottomSize = NSSize(width: 124, height: 86)
        public static let dropZoneSideSize = NSSize(width: 86, height: 124)
        public static let dragGhostSize: CGFloat = 30
    }

    /// The dictation waveform (§2.6) and the audio-level pipeline (§2.7).
    public enum Waveform {
        public static let barCount = 10
        public static let barWidth: CGFloat = 2
        public static let barMinHeight: CGFloat = 2
        public static let barRadius: CGFloat = 0.5
        public static let barGap: CGFloat = 2
        public static let containerHeight: CGFloat = 18
        public static let silentColor = NSColor.white.withAlphaComponent(0.4)
        public static let activeColor = NSColor.white
        /// `max(0, 1 − d² / 48)` with d = |4.5 − i|.
        public static let weights: [CGFloat] = (0..<10).map { i in max(0, 1 - pow(4.5 - CGFloat(i), 2) / 48) }
        public static let dictationGain: Float = 5
        public static let meetingGain: Float = 2
        /// Idle oscillation keyframes (time fraction, scale) over 1 s, ease-in-out, repeating.
        public static let oscillation: [(CGFloat, CGFloat)] = [(0, 1), (0.2, 1.2), (0.4, 1.5), (0.8, 1.1), (0.9, 1.3), (1, 1)]
        public static let phaseOffsets: [TimeInterval] = [0, 0.1, 0.2, 0.3, 0.4, -0.5, -0.4, -0.3, -0.2, -0.1]
        public static let levelFloorDB: Float = -60
        public static let levelRangeDB: Float = 20
        public static let levelBatchInterval: TimeInterval = 0.15
        public static let smoothingPerFrame: Double = 0.85
        public static let slewLimitPerSecond: Double = 1.6

        /// Meeting waveform (§10.2): 5 bars, linear bulge.
        public static let meetingBarCount = 5
        public static let meetingWeights: [CGFloat] = [0.25, 0.625, 1, 0.625, 0.25]
        public static let meetingMaxBarLength: CGFloat = 18
        public static let meetingBox: CGFloat = 24

        /// Mini waveform inside notifications.
        public static let miniGains: [CGFloat] = [0.8, 1, 1.2, 1, 0.8]
        public static let miniBoxHeight: CGFloat = 10

        /// Level 0…1 from a frame's dB after the adaptive floor (§2.7).
        public static func level(dB: Float, floor: Float) -> Float { min(max((dB - floor) / levelRangeDB, 0), 1) }
        /// `audioScale = max(1, gain × level)`.
        public static func scale(level: Float, gain: Float) -> CGFloat { CGFloat(max(1, gain * level)) }
    }

    /// The processing spinner (§2.8).
    public enum Spinner {
        public static let size: CGFloat = 16
        public static let spokes = 8
        public static let spokeSize = NSSize(width: 2, height: 5)
        public static let spokeRadius: CGFloat = 1
        public static let spokeOffset: CGFloat = 6
        public static let period: TimeInterval = 1.1
        public static let color = NSColor(srgbRed: 163 / 255, green: 148 / 255, blue: 199 / 255, alpha: 0.88)
        public static let fadedAlpha: CGFloat = 0.15
    }

    /// The hub window (§3).
    public enum Hub {
        public static let defaultSize = NSSize(width: 1350, height: 850)
        public static let minimumSize = NSSize(width: 1140, height: 750)
        public static let trafficLights = NSPoint(x: 16, y: 19)
        public static let headerHeight: CGFloat = 60
        public static let sidebarWidth: CGFloat = 216
        public static let sidebarCollapsedWidth: CGFloat = 60
        public static let sidebarFullScreenWidth: CGFloat = 256
        public static let sidebarPadding: CGFloat = 12
        public static let navItemPadding: CGFloat = 8
        public static let navItemRadius: CGFloat = 6
        public static let navIconSize: CGFloat = 20
        public static let navItemGap: CGFloat = 4
        public static let pageCornerRadii = (top: CGFloat(24), bottom: CGFloat(16))
        public static let pageMargin = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 8)
        public static let pagePadding = NSEdgeInsets(top: 40, left: 40, bottom: 0, right: 40)
        public static let contentMaxWidth: CGFloat = 1046
        public static let titleBottomMargin: CGFloat = 24
        public static let contentGap: CGFloat = 32
        public static let toastWidth: CGFloat = 300
        public static let menuMinWidth: CGFloat = 160
        public static let menuRadius: CGFloat = 10
        public static let keyPillHeight: CGFloat = 22
    }

    /// Buttons, switches and inputs (§3.3).
    public enum Controls {
        public static let buttonRadius: CGFloat = 8
        public static let buttonPadding = NSSize(width: 16, height: 8)
        public static let buttonHeightXS: CGFloat = 32
        public static let iconButtonSizes: [CGFloat] = [24, 28, 32, 56]
        public static let switchSize = NSSize(width: 42, height: 25)
        public static let switchThumb: CGFloat = 21
        public static let smallSwitchSize = NSSize(width: 24, height: 16)
        public static let inputHeight: CGFloat = 36
        public static let inputRadius: CGFloat = 8
        public static let modalRadius: CGFloat = 12
    }

    /// Settings modal (§4).
    public enum Settings {
        public static let size = NSSize(width: 960, height: 640)
        public static let sidebarWidth: CGFloat = 192
        public static let sidebarPadding: CGFloat = 8
        public static let itemMinHeight: CGFloat = 36
        public static let itemRadius: CGFloat = 8
        public static let radius: CGFloat = 12
    }

    /// Notepad window (§10.1): docked right at 30 % of the screen width.
    public enum Notepad {
        public static let screenWidthFraction: CGFloat = 0.3
        public static let minimumWidth: CGFloat = 360
    }

    /// Upcoming-meeting reminder pill (§10.3).
    public enum MeetingReminder {
        public static let restSize = NSSize(width: 30, height: 6)
        public static let miniSize = NSSize(width: 416, height: 48)
        public static let cardSize = NSSize(width: 416, height: 80)
        public static let miniRadius: CGFloat = 16
        public static let fill = NSColor(hex: "#1f1f1f")
        public static let borderWidth: CGFloat = 1.5
        public static let imminenceDotSize: CGFloat = 5
    }
}

// MARK: - Motion (§1.8, §2)

public enum SFMotion {
    /// Every Flow Bar size change: 100 ms, `cubic-bezier(0.05, 0.6, 0.4, 0.95)`.
    public static let snapDuration: TimeInterval = 0.1
    public static var snapTiming: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.05, 0.6, 0.4, 0.95) }
    /// Spring: overdamped, settles in ≈ 0.5 s; 150 ms for sidebars/switches/modals, 420 ms for notification morphs.
    public static let springShortDuration: TimeInterval = 0.15
    public static let springMorphDuration: TimeInterval = 0.42
    public static let springResponse: Double = 0.5
    public static let springDamping: Double = 1.0
    /// Material easing for post-Transform width/height changes (250–400 ms).
    public static var materialTiming: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) }
    public static let materialDuration: TimeInterval = 0.25
    public static let themeCrossFade: TimeInterval = 0.2
    public static let restingFade: TimeInterval = 0.1
    public static let tooltipFade: TimeInterval = 0.12
    public static let tooltipSlide: TimeInterval = 0.18
    public static let notificationColorDuration: TimeInterval = 0.22
    public static let notificationShadowDuration: TimeInterval = 0.3
    public static let waveformPeriod: TimeInterval = 1
    public static let meetingSizeDuration: TimeInterval = 0.16
    public static let meetingBorderDuration: TimeInterval = 0.13
    public static let meetingContentFade: TimeInterval = 0.06
    public static let meetingReconnectPulse: TimeInterval = 1.4
    public static let transformProgressDuration: TimeInterval = 7
    public static let transformProgressFinish: TimeInterval = 0.75
    public static let transformLabelCrossFade: TimeInterval = 0.28
    public static let dragOverlayFadeIn: TimeInterval = 0.12
    public static let dragOverlayFadeOut: TimeInterval = 0.2
    public static let dragGhostReturn: TimeInterval = 0.3
    public static let hubSidebarDuration: TimeInterval = 0.15
    public static let menuDuration: TimeInterval = 0.08
    public static let toastEnter: TimeInterval = 0.15
    public static let toastExit: TimeInterval = 0.8
    public static let rainbowRingPeriod: TimeInterval = 6
    public static let handsFreeToMeetingHold: TimeInterval = 10
}

/// Sound volumes (§8).
public enum SFSound {
    public static let dictationVolume: Float = 1
    public static let notificationVolume: Float = 0.5
}

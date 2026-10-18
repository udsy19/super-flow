import AppKit
import SuperFlowCore

// The Flow Bar's timing curves, waveform and spinner maths, and the audio-level smoother (ui-reference.md §1.8,
// §2.6–2.8, §10.2). Pure functions of time so the canvas, the offscreen renders and the self-tests agree.

/// An easing curve mapping progress 0…1 to 0…1 (values may overshoot for springs).
public struct TimingCurve: Sendable {
    private let map: @Sendable (Double) -> Double

    public init(_ map: @escaping @Sendable (Double) -> Double) { self.map = map }

    public func callAsFunction(_ x: Double) -> Double { map(min(max(x, 0), 1)) }

    public static let linear = TimingCurve { $0 }
    /// Every Flow Bar size change: `cubic-bezier(0.05, 0.6, 0.4, 0.95)` over 100 ms (§1.8).
    public static let snap = cubicBezier(0.05, 0.6, 0.4, 0.95)
    /// Post-Transform width/height (§1.8).
    public static let material = cubicBezier(0.4, 0, 0.2, 1)
    /// CSS `ease` (tooltip slide, card colours).
    public static let ease = cubicBezier(0.25, 0.1, 0.25, 1)
    /// CSS `ease-in-out`, applied per keyframe interval (waveform oscillation, reconnect pulse).
    public static let easeInOut = cubicBezier(0.42, 0, 0.58, 1)
    /// `--spring-easing` (§1.8): overdamped, for notification morphs (420 ms).
    public static let spring = cssLinear([
        (0, 0), (0.005, nil), (0.019, 1.8), (0.079, 3.9), (0.476, 13.5), (0.663, 19.1), (0.738, 22), (0.8, 25.1),
        (0.852, 28.4), (0.894, 32), (0.928, 36), (0.953, 40.5), (0.972, 45.6), (0.985, 51.6), (0.997, 67.3), (1, 100),
    ])
    /// Smoothstep, for the meeting waveform's per-bar ticker (§10.2).
    public static let smoothstep = TimingCurve { $0 * $0 * (3 - 2 * $0) }

    /// A CSS `cubic-bezier(x1, y1, x2, y2)`: solves x(t) = progress with Newton steps, bisection as the fallback.
    public static func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> TimingCurve {
        @Sendable func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        @Sendable func slope(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
        }
        return TimingCurve { x in
            var t = x
            for _ in 0..<8 {
                let error = bezier(t, x1, x2) - x
                if abs(error) < 1e-6 { return bezier(t, y1, y2) }
                let d = slope(t, x1, x2)
                if abs(d) < 1e-6 { break }
                t -= error / d
            }
            var lo = 0.0, hi = 1.0
            t = x
            for _ in 0..<40 {
                let value = bezier(t, x1, x2)
                if abs(value - x) < 1e-7 { break }
                if value < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
            return bezier(t, y1, y2)
        }
    }

    /// A CSS `linear(…)` easing: stops are (output, input %); a stop without a position is spaced evenly between its
    /// positioned neighbours, as the CSS spec resolves them.
    public static func cssLinear(_ stops: [(Double, Double?)]) -> TimingCurve {
        var positions = stops.map { $0.1.map { $0 / 100 } }
        if positions.first.flatMap({ $0 }) == nil { positions[0] = 0 }
        if positions.last.flatMap({ $0 }) == nil { positions[positions.count - 1] = 1 }
        var i = 0
        while i < positions.count {
            if positions[i] == nil {
                let start = i - 1
                var end = i
                while positions[end] == nil { end += 1 }
                let a = positions[start]!, b = positions[end]!
                for k in i..<end { positions[k] = a + (b - a) * Double(k - start) / Double(end - start) }
                i = end
            }
            i += 1
        }
        let points = zip(positions.map { $0! }, stops.map(\.0)).map { (x: $0, y: $1) }
        return TimingCurve { x in
            guard let upper = points.firstIndex(where: { $0.x >= x }) else { return points.last!.y }
            if upper == 0 { return points[0].y }
            let a = points[upper - 1], b = points[upper]
            return b.x == a.x ? b.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
    }
}

/// Waveform, spinner and pulse maths.
public enum FlowBarMotion {
    /// The idle oscillation multiplier `k` at a phase 0…1 of the 1 s cycle (§2.6): keyframes with the curve applied
    /// inside each keyframe interval, as CSS animations do.
    public static func oscillation(phase: Double, curve: TimingCurve = .easeInOut) -> CGFloat {
        let frames = SFMetrics.Waveform.oscillation
        let p = phase - floor(phase)
        for (a, b) in zip(frames, frames.dropFirst()) where p >= Double(a.0) && p <= Double(b.0) {
            let span = Double(b.0 - a.0)
            let local = span > 0 ? (p - Double(a.0)) / span : 0
            return a.1 + (b.1 - a.1) * CGFloat(curve(local))
        }
        return 1
    }

    /// Lengths of the ten dictation bars (§2.6). Silent bars are 2 pt dots; while speech is detected each bar is
    /// `2 × audioScale × weight × k`, with `k` the oscillation at the bar's phase offset (1 when motion is reduced).
    public static func dictationBars(audioScale: CGFloat, time: TimeInterval, speaking: Bool, reduceMotion: Bool) -> [CGFloat] {
        let base = SFMetrics.Waveform.barMinHeight
        guard speaking else { return Array(repeating: base, count: SFMetrics.Waveform.barCount) }
        return SFMetrics.Waveform.weights.enumerated().map { i, weight in
            let k = reduceMotion ? 1 : oscillation(phase: (time - SFMetrics.Waveform.phaseOffsets[i]) / SFMotion.waveformPeriod)
            return max(base, base * audioScale * weight * k)
        }
    }

    /// Lengths of the five meeting bars (§10.2): `6 × audioScale × weight × waveMult`, capped at 18; 2 when silent.
    public static func meetingBars(audioScale: CGFloat, time: TimeInterval, speaking: Bool, reduceMotion: Bool) -> [CGFloat] {
        let offsets: [TimeInterval] = [0, 0.1, 0.2, -0.2, -0.1]
        return SFMetrics.Waveform.meetingWeights.enumerated().map { i, weight in
            guard speaking else { return SFMetrics.Waveform.barMinHeight }
            let mult = reduceMotion ? 1 : oscillation(phase: (time - offsets[i]) / SFMotion.waveformPeriod, curve: .smoothstep)
            return min(SFMetrics.Waveform.meetingMaxBarLength, max(SFMetrics.Waveform.barMinHeight, 6 * audioScale * weight * mult))
        }
    }

    /// Opacity of spoke `i` (0…7) of the processing spinner (§2.8): each fades .88 → .15 over 1.1 s, delayed by
    /// −0.1375 × (7 − i) s, so the brightest spoke walks clockwise.
    public static func spinnerAlpha(spoke i: Int, time: TimeInterval) -> CGFloat {
        let period = SFMetrics.Spinner.period
        let t = time + 0.1375 * Double(7 - i)
        let phase = (t - floor(t / period) * period) / period
        return 0.88 + (SFMetrics.Spinner.fadedAlpha - 0.88) * CGFloat(phase)
    }

    /// The reconnecting meeting pill pulses opacity 1 ↔ .6 over 1.4 s (§10.2).
    public static func reconnectPulse(time: TimeInterval) -> CGFloat {
        let p = time / SFMotion.meetingReconnectPulse
        let phase = p - floor(p)
        let half = phase < 0.5 ? phase * 2 : (1 - phase) * 2
        return 1 - 0.4 * CGFloat(TimingCurve.easeInOut(half))
    }

    /// "0:07", "12:05", "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// The bar-side half of the audio-level pipeline (§2.7): exponential smoothing per frame, a slew limit of 1.6/s,
/// and `audioScale = max(1, gain × level)`. Speech is "detected" with hysteresis so the bars don't flicker.
public struct LevelSmoother: Equatable, Sendable {
    public private(set) var value: Double = 0
    public var target: Double = 0
    public private(set) var speaking = false

    /// Above this the bars animate; below `speechOff` they fall back to dots.
    public static let speechOn = 0.06
    public static let speechOff = 0.03

    public init() {}

    /// A level already settled at `level` (renders and tests).
    public init(settledAt level: Double) {
        value = min(max(level, 0), 1); target = value; speaking = value > LevelSmoother.speechOn
    }

    /// Whether another frame would change anything.
    public var isSettled: Bool { value == 0 && target == 0 }

    public mutating func step(dt: TimeInterval) {
        let dt = min(max(dt, 0.001), 0.2)
        let k = pow(SFMetrics.Waveform.smoothingPerFrame, dt / (1.0 / 60))
        let smoothed = value * k + target * (1 - k)
        let limit = SFMetrics.Waveform.slewLimitPerSecond * dt
        var next = value + min(max(smoothed - value, -limit), limit)
        if next < 0.01 && target == 0 { next = 0 }
        value = min(max(next, 0), 1)
        if speaking ? value < LevelSmoother.speechOff : value > LevelSmoother.speechOn { speaking.toggle() }
    }

    public func audioScale(gain: Float) -> CGFloat { SFMetrics.Waveform.scale(level: Float(value), gain: gain) }
}

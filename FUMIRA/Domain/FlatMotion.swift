import CoreGraphics
import Foundation

// MARK: - Waveform geometry

/// Deterministic continuous waveform for ``WaveTimeRail``.
///
/// For bar count `N`, normalized value `s`, and continuous index `u`:
/// `u = ((clamp(s,-1,1)+1)/2)*(N-1)`, `d = index - u`,
/// `G = exp(-0.5*(d/3.6)^2)`, `R = 0.84 + 0.16*cos(1.15*d)`.
enum WaveformGeometry {
    static let defaultBarCount = 33
    static let envelopeSigma = 3.6
    static let rhythmFrequency = 1.15
    static let ordinaryCapRatio = 0.78
    static let activePeakRatio = 1.0

    static func continuousIndex(
        normalized s: Double,
        barCount: Int = defaultBarCount
    ) -> Double {
        let clamped = min(max(s, -1), 1)
        return ((clamped + 1) / 2) * Double(barCount - 1)
    }

    static func envelope(distance d: Double) -> Double {
        exp(-0.5 * pow(d / envelopeSigma, 2))
    }

    static func rhythm(distance d: Double) -> Double {
        0.84 + 0.16 * cos(rhythmFrequency * d)
    }

    static func ordinaryRelativeHeight(
        at index: Int,
        selectedIndex u: Double
    ) -> Double {
        let d = Double(index) - u
        let raw = envelope(distance: d) * rhythm(distance: d)
        return min(ordinaryCapRatio, raw)
    }

    static func ordinaryHeights(
        normalized s: Double,
        barCount: Int = defaultBarCount
    ) -> [Double] {
        let u = continuousIndex(normalized: s, barCount: barCount)
        return (0..<barCount).map { ordinaryRelativeHeight(at: $0, selectedIndex: u) }
    }

    static func maxOrdinaryHeight(
        normalized s: Double,
        barCount: Int = defaultBarCount
    ) -> Double {
        ordinaryHeights(normalized: s, barCount: barCount).max() ?? 0
    }

    /// Active thumb capsule is always the unique tallest element.
    static func isActivePeakUnique(
        normalized s: Double,
        barCount: Int = defaultBarCount
    ) -> Bool {
        maxOrdinaryHeight(normalized: s, barCount: barCount) < activePeakRatio
    }

    static func maxOrdinaryDelta(
        between first: Double,
        and second: Double,
        barCount: Int = defaultBarCount
    ) -> Double {
        let left = ordinaryHeights(normalized: first, barCount: barCount)
        let right = ordinaryHeights(normalized: second, barCount: barCount)
        return zip(left, right).map { abs($0 - $1) }.max() ?? 0
    }
}

// MARK: - Render publication gate

/// The waveform follows a finger from view-local state, while the app model
/// only needs periodic semantic updates (Live Activity, capture target, etc.).
/// Limiting those writes avoids invalidating the entire viewfinder on every
/// touch sample without adding visible latency to the rail itself.
enum WaveTimeModelPublicationGate {
    static let minimumInterval: TimeInterval = 1.0 / 30.0

    static func shouldPublish(
        lastPublishedAt: Date,
        now: Date,
        minimumInterval: TimeInterval = minimumInterval
    ) -> Bool {
        now.timeIntervalSince(lastPublishedAt) >= minimumInterval
    }
}

// MARK: - Shutter morph geometry

enum ShutterMorphGeometry {
    static func easedProgress(_ progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    static func size(
        progress: CGFloat,
        shutterDiameter: CGFloat,
        barWidth: CGFloat,
        barHeight: CGFloat
    ) -> CGSize {
        let eased = easedProgress(progress)
        return CGSize(
            width: shutterDiameter + (barWidth - shutterDiameter) * eased,
            height: shutterDiameter + (barHeight - shutterDiameter) * eased
        )
    }

    static func horizontalEdges(centerX: CGFloat, width: CGFloat) -> ClosedRange<CGFloat> {
        (centerX - width / 2)...(centerX + width / 2)
    }
}

// MARK: - VoiceOver adjustment

enum WaveTimeAccessibilityAdjustment {
    enum Direction: Sendable {
        case increment
        case decrement
    }

    /// Adjusts in offset-day space so NOW moves by ±1 day instead of snapping to zero.
    static func adjustedOffsetDays(
        from currentDays: Double,
        direction: Direction
    ) -> Double {
        let step = stepDays(for: currentDays)
        let delta = direction == .increment ? step : -step
        let next = currentDays + delta
        return min(max(next, -TimePosition.maximumOffsetDays), TimePosition.maximumOffsetDays)
    }

    static func adjustedNormalized(
        from currentNormalized: Double,
        direction: Direction
    ) -> Double {
        let days = TimePosition(normalized: currentNormalized).offsetDays
        let nextDays = adjustedOffsetDays(from: days, direction: direction)
        return TimePosition(offsetDays: nextDays).normalized
    }

    static func stepDays(for offsetDays: Double) -> Double {
        let magnitude = abs(offsetDays)
        if magnitude < 0.5 { return 1 }
        if magnitude < 31 { return 1 }
        if magnitude < 365.25 { return 7 }
        if magnitude < 3_652.5 { return 30.44 }
        return 365.25
    }
}

// MARK: - Haptic crossings

enum WaveTimeDetent: Sendable, Equatable {
    case decade
    case now
}

enum WaveTimeHapticCrossing {
    /// Signed decade bucket; `0` is the NOW band or pre-first-decade range.
    static func bucket(for offsetYears: Double) -> Int {
        if abs(offsetYears) < 0.5 { return 0 }
        if offsetYears > 0 {
            return Int(floor(offsetYears / 10.0)) * 10
        }
        return Int(ceil(offsetYears / 10.0)) * 10
    }

    /// Returns `true` when a sparse tick should fire after the first baseline sample.
    static func shouldTick(
        previousYears: Double,
        currentYears: Double
    ) -> Bool {
        if crossedNow(previousYears: previousYears, currentYears: currentYears) {
            return true
        }

        let previousBucket = bucket(for: previousYears)
        let currentBucket = bucket(for: currentYears)
        return previousBucket != currentBucket
    }

    static func crossedNow(
        previousYears: Double,
        currentYears: Double
    ) -> Bool {
        (previousYears < 0 && currentYears >= 0)
            || (previousYears > 0 && currentYears <= 0)
    }
}

// MARK: - Decorative parallax

enum FlatMotionLayerDepth: Int, Sendable, CaseIterable {
    case back
    case mid
    case front

    var parallaxPoints: CGFloat {
        switch self {
        case .back: 1.5
        case .mid: 3.0
        case .front: 5.0
        }
    }
}

enum FlatMotionParallax {
    static let maxRotationDegrees = 0.75
    static let updateInterval: Duration = .milliseconds(40)
}

import Foundation

enum TemporalBlinkFrame: Hashable, Sendable {
    case original
    case generated

    var opposite: TemporalBlinkFrame {
        self == .original ? .generated : .original
    }
}

struct TemporalBlinkStep: Hashable, Sendable {
    let frame: TemporalBlinkFrame
    /// Delay before this frame is presented.
    let delay: Duration
}

/// Pure policy for astronomical blink comparison.
///
/// The engine never starts work itself. A cadence is returned only for an
/// explicit user request, contains one finite round, and stays comfortably
/// below high-frequency flashing thresholds.
struct TemporalBlinkComparatorEngine: Hashable, Sendable {
    static let minimumDwell = Duration.milliseconds(650)
    static let standard = TemporalBlinkComparatorEngine()

    let dwell: Duration

    init(dwell: Duration = .milliseconds(700)) {
        self.dwell = max(dwell, Self.minimumDwell)
    }

    func visibleFrame(
        lockedFrame: TemporalBlinkFrame,
        isHoldingOriginal: Bool,
        cadenceFrame: TemporalBlinkFrame?
    ) -> TemporalBlinkFrame {
        if isHoldingOriginal {
            return .original
        }
        return cadenceFrame ?? lockedFrame
    }

    func toggled(_ frame: TemporalBlinkFrame) -> TemporalBlinkFrame {
        frame.opposite
    }

    /// One user-triggered comparison round. It never repeats automatically.
    func blinkPlan(
        startingFrom frame: TemporalBlinkFrame,
        reduceMotion: Bool,
        dimFlashingLights: Bool
    ) -> [TemporalBlinkStep] {
        guard !reduceMotion, !dimFlashingLights else { return [] }

        return [
            TemporalBlinkStep(frame: frame.opposite, delay: .zero),
            TemporalBlinkStep(frame: frame, delay: dwell),
            TemporalBlinkStep(frame: frame.opposite, delay: dwell),
            TemporalBlinkStep(frame: frame, delay: dwell),
        ]
    }
}

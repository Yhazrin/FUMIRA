import Foundation
import Observation

/// Secondary, opt-in hands-free time browsing.
///
/// Extracted from `ResultView` so the five pieces of tilt bookkeeping live with
/// the rule that uses them rather than beside unrelated result-screen state.
/// The controller owns no view; it maps device roll to a `TimePosition` and
/// reports whether a haptic detent was crossed.
@Observable
final class ResultTiltTimeController {

    private(set) var isActive = false

    /// Frozen browse position while tilt is driving the rail.
    ///
    /// Tilt updates at sensor rate. Rebuilding narrative, actions, and branches
    /// thirty times per second is both wasteful and visually unstable, so the
    /// rest of the page reads this snapshot and commits once tilt stops.
    private(set) var structureTime: TimePosition?

    private var baselineRoll: Double?
    private var lastSampleTime: TimeInterval?
    private var lastHapticYears: Double?

    struct Advance {
        let time: TimePosition
        let detent: WaveTimeDetent?
    }

    func start(from time: TimePosition) {
        isActive = true
        structureTime = time
        // The first sensor sample after opt-in establishes a real baseline.
        // Reusing the observable's initial zero can otherwise jump time on
        // hardware whose current attitude has not been published yet.
        baselineRoll = nil
        lastSampleTime = nil
        lastHapticYears = time.offsetYears
    }

    func stop() {
        isActive = false
        structureTime = nil
        baselineRoll = nil
        lastSampleTime = nil
        lastHapticYears = nil
    }

    /// Returns the next position, or `nil` when the sample should be absorbed
    /// (establishing a baseline, inactive, or no meaningful movement).
    func advance(
        from current: TimePosition,
        roll: Double,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Advance? {
        guard isActive, roll.isFinite else { return nil }

        guard let baselineRoll, let lastSampleTime else {
            self.baselineRoll = roll
            self.lastSampleTime = now
            return nil
        }
        self.lastSampleTime = now

        let next = TiltTimeNavigator.standard.advance(
            current,
            rollRadians: Self.signedAngularDelta(roll, baselineRoll),
            frameDelta: now - lastSampleTime
        )
        guard next != current else { return nil }

        let previousYears = lastHapticYears ?? current.offsetYears
        lastHapticYears = next.offsetYears

        guard WaveTimeHapticCrossing.shouldTick(
            previousYears: previousYears,
            currentYears: next.offsetYears
        ) else {
            return Advance(time: next, detent: nil)
        }

        let crossedNow = WaveTimeHapticCrossing.crossedNow(
            previousYears: previousYears,
            currentYears: next.offsetYears
        )
        return Advance(time: next, detent: crossedNow ? .now : .decade)
    }

    static func signedAngularDelta(_ current: Double, _ baseline: Double) -> Double {
        var delta = current - baseline
        while delta > .pi { delta -= .pi * 2 }
        while delta < -.pi { delta += .pi * 2 }
        return delta
    }
}

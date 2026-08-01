import Foundation

/// Pure tilt-to-time mapping for continuous time navigation.
///
/// Positive roll moves toward the future and negative roll moves toward the
/// past. The dead zone produces no movement; beyond it, velocity increases
/// smoothly until reaching the configured maximum.
struct TiltTimeNavigator: Hashable, Sendable {
    static let standard = TiltTimeNavigator()

    let deadZoneRadians: Double
    let fullSpeedTiltRadians: Double
    let maximumNormalizedVelocity: Double
    let maximumFrameDelta: TimeInterval

    init(
        deadZoneRadians: Double = 0.06,
        fullSpeedTiltRadians: Double = 0.55,
        maximumNormalizedVelocity: Double = 0.45,
        maximumFrameDelta: TimeInterval = 0.1
    ) {
        let safeDeadZone = Self.nonnegativeFinite(deadZoneRadians, fallback: 0.06)
        self.deadZoneRadians = safeDeadZone
        self.fullSpeedTiltRadians = max(
            Self.nonnegativeFinite(fullSpeedTiltRadians, fallback: 0.55),
            safeDeadZone + 0.000_001
        )
        self.maximumNormalizedVelocity = Self.nonnegativeFinite(
            maximumNormalizedVelocity,
            fallback: 0.45
        )
        self.maximumFrameDelta = Self.nonnegativeFinite(maximumFrameDelta, fallback: 0.1)
    }

    /// Returns the next bounded position for one motion sample.
    func advance(
        _ position: TimePosition,
        rollRadians: Double,
        frameDelta: TimeInterval
    ) -> TimePosition {
        guard position.normalized.isFinite,
              rollRadians.isFinite,
              frameDelta.isFinite,
              frameDelta > 0 else {
            return position.normalized.isFinite ? position : .now
        }

        let boundedDelta = min(frameDelta, maximumFrameDelta)
        let delta = normalizedVelocity(for: rollRadians) * boundedDelta
        return TimePosition(normalized: position.normalized + delta)
    }

    /// Normalized time-axis units traveled per second for a roll sample.
    func normalizedVelocity(for rollRadians: Double) -> Double {
        guard rollRadians.isFinite else { return 0 }

        let magnitude = abs(rollRadians)
        guard magnitude > deadZoneRadians else { return 0 }

        let availableRange = fullSpeedTiltRadians - deadZoneRadians
        let linearProgress = min((magnitude - deadZoneRadians) / availableRange, 1)
        let smoothProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
        return rollRadians.sign == .minus
            ? -maximumNormalizedVelocity * smoothProgress
            : maximumNormalizedVelocity * smoothProgress
    }

    private static func nonnegativeFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? max(value, 0) : fallback
    }
}

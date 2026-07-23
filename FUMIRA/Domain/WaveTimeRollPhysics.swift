import Foundation

/// Small, bounded release physics for the time rail.
///
/// The rail follows a finger exactly while dragging. On release it travels a
/// tiny distance in the release direction, then locks back on the snapped date.
/// Values are normalized so the same behavior works across all device widths.
enum WaveTimeRollPhysics {
    static let maximumKick = 0.018
    static let minimumKick = 0.004

    static func releaseDirection(current: Double, predicted: Double) -> Double {
        let delta = predicted - current
        guard abs(delta) > 0.000_5 else { return 0 }
        return delta < 0 ? -1 : 1
    }

    static func releaseKick(current: Double, predicted: Double) -> Double {
        let travel = abs(predicted - current)
        guard travel > 0.000_5 else { return 0 }
        return min(maximumKick, max(minimumKick, travel * 0.14))
    }

    static func overshoot(target: Double, direction: Double, kick: Double) -> Double {
        min(max(target + direction * kick, -1), 1)
    }

    static func impact(for kick: Double) -> Double {
        min(max(kick / maximumKick, 0), 1)
    }
}

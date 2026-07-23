import SwiftUI

enum PosterMotion {
    // Durations (seconds) — flat poster motion language
    static let microMin = 0.10
    static let microMax = 0.22
    static let entranceMin = 0.45
    static let entranceMax = 0.65
    static let exitFactor = 0.75

    static let micro = 0.18
    static let entrance = 0.55
    static let exit = entrance * exitFactor
    static let timeFlow = 0.34
    static let timeRailKickDuration = 0.07
    static let timeRailSettleDuration = 0.20
    static let poster = entrance
    static let page = 0.52
    static let reduced = 0.15
    static let cameraInputGuard = Duration.milliseconds(320)

    static let decelerate = Animation.timingCurve(0.22, 1, 0.36, 1, duration: entrance)
    static let interaction = Animation.timingCurve(0.33, 1, 0.68, 1, duration: micro)
    static let exitAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: exit)
    static let press = interaction
    static let flow = Animation.timingCurve(0.33, 1, 0.68, 1, duration: timeFlow)
    /// A firm, non-bouncy impulse for the physical time-wheel lock.
    static let timeRailKick = Animation.timingCurve(0.12, 0.94, 0.20, 1, duration: timeRailKickDuration)
    static let timeRailSettle = Animation.timingCurve(0.18, 0.86, 0.24, 1, duration: timeRailSettleDuration)
    static let pageTransition = Animation.timingCurve(0.22, 1, 0.36, 1, duration: page)
    static let aperture = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.58)
    static let shutter = Animation.timingCurve(0.7, 0, 0.84, 0, duration: 0.2)
    static let reveal = Animation.timingCurve(0.12, 0.78, 0.18, 1, duration: 0.72)
}

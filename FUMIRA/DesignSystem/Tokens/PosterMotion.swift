import SwiftUI

enum PosterMotion {
    static let micro = 0.18
    static let timeFlow = 0.34
    static let poster = 0.42
    static let page = 0.52
    static let reduced = 0.15
    static let cameraInputGuard = Duration.milliseconds(320)

    static let press = Animation.spring(response: micro, dampingFraction: 0.58)
    static let flow = Animation.spring(response: timeFlow, dampingFraction: 0.78)
    static let pageTransition = Animation.spring(response: page, dampingFraction: 0.82)
}

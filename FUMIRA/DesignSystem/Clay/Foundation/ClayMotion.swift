import SwiftUI

/// Animation and spring tokens for Clay OS.
/// Clay interaction timing. Direct manipulation stays quick and controlled;
/// larger spatial transitions may still use springs.
enum ClayMotion {

    // MARK: - Springs

    /// Button press / release feedback.
    static let buttonSpring = Animation.smooth(duration: 0.18)

    /// Panel / card entrance.
    static let panelSpring = Animation.spring(response: 0.35, dampingFraction: 0.70)

    /// Toggle / state change.
    static let toggleSpring = Animation.spring(response: 0.32, dampingFraction: 0.68)

    /// Subtle hover / focus.
    static let hoverSpring = Animation.spring(response: 0.28, dampingFraction: 0.75)

    /// Progress bar fill.
    static let progressSpring = Animation.spring(response: 0.50, dampingFraction: 0.80)

    // MARK: - Transitions

    static let pressScale: CGFloat = 0.995
    static let pressOffsetY: CGFloat = 4

    // MARK: - Duration (for non-spring animations)

    static let durationFast: Double = 0.15
    static let durationMedium: Double = 0.25
    static let durationSlow: Double = 0.40
}

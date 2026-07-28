import SwiftUI

struct PosterPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .animation(reduceMotion ? .linear(duration: PosterMotion.reduced) : PosterMotion.press, value: configuration.isPressed)
    }
}

struct PosterCapsulePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .animation(reduceMotion ? .linear(duration: PosterMotion.reduced) : PosterMotion.press, value: configuration.isPressed)
    }
}

/// Poster entry controls compress vertically like a physical shutter plate.
/// Kept in DesignSystem so reusable buttons do not depend on ConnectionView.
struct ConnectionStartPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: 1,
                y: reduceMotion || !configuration.isPressed ? 1 : 0.94
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion
                    ? .linear(duration: PosterMotion.reduced)
                    : PosterMotion.press,
                value: configuration.isPressed
            )
    }
}

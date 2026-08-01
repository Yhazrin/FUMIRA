import SwiftUI

/// Clay button style — native SwiftUI ButtonStyle with physical depth feedback.
/// Press compresses shadow, sinks, and scales slightly.
struct ClayButtonStyle: ButtonStyle {
    let base: Color
    let rim: Color
    let foreground: Color
    let cornerRadius: CGFloat

    init(
        base: Color = ClayPalette.orange,
        rim: Color = ClayPalette.orangeRim,
        foreground: Color = ClayPalette.charcoal,
        cornerRadius: CGFloat = ClayShape.button
    ) {
        self.base = base
        self.rim = rim
        self.foreground = foreground
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background {
                ZStack {
                    // Rim
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(rim)
                        .offset(y: configuration.isPressed
                            ? ClayShape.rimOffsetPressed
                            : ClayShape.rimOffset)

                    // Face
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(base)
                        .overlay {
                            LinearGradient(
                                stops: ClayShadow.highlightStops,
                                startPoint: ClayShadow.highlightStart,
                                endPoint: ClayShadow.highlightEnd
                            )
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                        .overlay {
                            ClayNoiseTexture(opacity: 0.17)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: ClayShadow.edgeStrokeColors,
                                        startPoint: ClayShadow.edgeStrokeStart,
                                        endPoint: ClayShadow.edgeStrokeEnd
                                    ),
                                    lineWidth: 2
                                )
                        }
                }
            }
            .shadow(
                color: configuration.isPressed
                    ? ClayShadow.pressed.color
                    : ClayShadow.rest.color,
                radius: configuration.isPressed
                    ? ClayShadow.pressed.radius
                    : ClayShadow.rest.radius,
                x: 0,
                y: configuration.isPressed
                    ? ClayShadow.pressed.y
                    : ClayShadow.rest.y
            )
            .scaleEffect(configuration.isPressed ? ClayMotion.pressScale : 1)
            .offset(y: configuration.isPressed ? ClayMotion.pressOffsetY : 0)
            .animation(ClayMotion.buttonSpring, value: configuration.isPressed)
    }
}

// MARK: - Convenience view modifier

extension View {
    func clayButtonStyle(
        base: Color = ClayPalette.orange,
        rim: Color = ClayPalette.orangeRim,
        foreground: Color = ClayPalette.charcoal,
        cornerRadius: CGFloat = ClayShape.button
    ) -> some View {
        self.buttonStyle(
            ClayButtonStyle(
                base: base,
                rim: rim,
                foreground: foreground,
                cornerRadius: cornerRadius
            )
        )
    }
}

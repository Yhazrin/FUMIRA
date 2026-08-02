import SwiftUI

/// A molded toy button: the housing stays fixed while the face travels into it.
/// The restrained highlight and soft contact shadow keep the material closer to
/// vinyl clay than to a hard, glossy plastic slab.
struct ClayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let base: Color
    let rim: Color
    let foreground: Color
    let cornerRadius: CGFloat
    let depth: CGFloat

    init(
        base: Color = ClayPalette.orange,
        rim: Color = ClayPalette.orangeRim,
        foreground: Color = ClayPalette.charcoal,
        cornerRadius: CGFloat = ClayShape.button,
        depth: CGFloat = 6
    ) {
        self.base = base
        self.rim = rim
        self.foreground = foreground
        self.cornerRadius = cornerRadius
        self.depth = depth
    }

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled

        return ClayMoldedControl(
            base: base,
            rim: rim,
            foreground: foreground,
            cornerRadius: cornerRadius,
            depth: depth,
            isPressed: isPressed
        ) {
            configuration.label
        }
            .shadow(
                color: isPressed
                    ? ClayShadow.buttonPressed.color
                    : ClayShadow.buttonRest.color,
                radius: isPressed
                    ? ClayShadow.buttonPressed.radius
                    : ClayShadow.buttonRest.radius,
                x: 0,
                y: isPressed
                    ? ClayShadow.buttonPressed.y
                    : ClayShadow.buttonRest.y
            )
            .opacity(isEnabled ? 1 : 0.46)
            .contentShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .animation(
                reduceMotion ? .linear(duration: 0.01) : ClayMotion.buttonSpring,
                value: isPressed
            )
    }
}

/// Resting or pressed molded face, also reusable by non-Button controls such as Menu labels.
struct ClayMoldedControl<Label: View>: View {
    let base: Color
    let rim: Color
    let foreground: Color
    let cornerRadius: CGFloat
    let depth: CGFloat
    let isPressed: Bool
    @ViewBuilder let label: Label

    private var faceTravel: CGFloat {
        isPressed ? max(depth - 1, 0) : 0
    }

    var body: some View {
        ZStack {
            label
                .hidden()
                .accessibilityHidden(true)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(rim)
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .clipShape(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            )
                        }
                }
                .offset(y: depth)

            label
                .foregroundStyle(foreground)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(base)
                        .overlay {
                            ClayNoiseTexture(opacity: 0.035)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: ClayShadow.edgeStrokeColors,
                                        startPoint: ClayShadow.edgeStrokeStart,
                                        endPoint: ClayShadow.edgeStrokeEnd
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .offset(y: faceTravel)
        }
    }
}

// MARK: - Convenience view modifier

extension View {
    func clayButtonStyle(
        base: Color = ClayPalette.orange,
        rim: Color = ClayPalette.orangeRim,
        foreground: Color = ClayPalette.charcoal,
        cornerRadius: CGFloat = ClayShape.button,
        depth: CGFloat = 6
    ) -> some View {
        self.buttonStyle(
            ClayButtonStyle(
                base: base,
                rim: rim,
                foreground: foreground,
                cornerRadius: cornerRadius,
                depth: depth
            )
        )
    }
}

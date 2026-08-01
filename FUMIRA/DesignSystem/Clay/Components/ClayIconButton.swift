import SwiftUI

/// Clay icon button — small round or squircle button for SF Symbols.
struct ClayIconButton: View {
    let systemName: String
    let base: Color
    let rim: Color
    let foreground: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void

    init(
        systemName: String,
        base: Color = ClayPalette.warmWhite,
        rim: Color = ClayPalette.warmWhiteRim,
        foreground: Color = ClayPalette.charcoal,
        size: CGFloat = 44,
        cornerRadius: CGFloat = ClayShape.sm,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.base = base
        self.rim = rim
        self.foreground = foreground
        self.size = size
        self.cornerRadius = cornerRadius
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(rim)
                            .offset(y: ClayShape.rimOffset - 2)

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
                                ClayNoiseTexture(opacity: 0.12)
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
                                        lineWidth: 1.5
                                    )
                            }
                    }
                }
                .shadow(
                    color: ClayShadow.small.color,
                    radius: ClayShadow.small.radius,
                    x: ClayShadow.small.x,
                    y: ClayShadow.small.y
                )
        }
        .buttonStyle(.plain)
    }
}

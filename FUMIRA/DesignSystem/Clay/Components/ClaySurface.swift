import SwiftUI

/// Base clay surface with rim, highlight, grain, and shadow.
/// All clay components build on this.
struct ClaySurface: View {
    let base: Color
    let rim: Color
    let cornerRadius: CGFloat
    let shadowSpec: ClayShadow.ShadowSpec

    init(
        base: Color = ClayPalette.warmWhite,
        rim: Color = ClayPalette.warmWhiteRim,
        cornerRadius: CGFloat = ClayShape.card,
        shadow: ClayShadow.ShadowSpec = ClayShadow.rest
    ) {
        self.base = base
        self.rim = rim
        self.cornerRadius = cornerRadius
        self.shadowSpec = shadow
    }

    var body: some View {
        ZStack {
            // Rim (darker lower layer)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(rim)
                .offset(y: ClayShape.rimOffset)

            // Main face
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(base)
                // Top highlight gradient
                .overlay {
                    LinearGradient(
                        stops: ClayShadow.highlightStops,
                        startPoint: ClayShadow.highlightStart,
                        endPoint: ClayShadow.highlightEnd
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                // Grain texture
                .overlay {
                    ClayNoiseTexture(opacity: 0.04)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                // Edge stroke
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: ClayShadow.edgeStrokeColors,
                                startPoint: ClayShadow.edgeStrokeStart,
                                endPoint: ClayShadow.edgeStrokeEnd
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(
            color: shadowSpec.color,
            radius: shadowSpec.radius,
            x: shadowSpec.x,
            y: shadowSpec.y
        )
    }
}

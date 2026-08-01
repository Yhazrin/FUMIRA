import SwiftUI

/// Clay panel — a container with clay surface styling.
/// Use for content blocks that need physical depth.
struct ClayPanel<Content: View>: View {
    let base: Color
    let rim: Color
    let cornerRadius: CGFloat
    let shadowSpec: ClayShadow.ShadowSpec
    let content: Content

    init(
        base: Color = ClayPalette.warmWhite,
        rim: Color = ClayPalette.warmWhiteRim,
        cornerRadius: CGFloat = ClayShape.panel,
        shadow: ClayShadow.ShadowSpec = ClayShadow.rest,
        @ViewBuilder content: () -> Content
    ) {
        self.base = base
        self.rim = rim
        self.cornerRadius = cornerRadius
        self.shadowSpec = shadow
        self.content = content()
    }

    var body: some View {
        content
            .padding(ClaySpacing.panelPadding)
            .background {
                ClaySurface(
                    base: base,
                    rim: rim,
                    cornerRadius: cornerRadius,
                    shadow: shadowSpec
                )
            }
    }
}

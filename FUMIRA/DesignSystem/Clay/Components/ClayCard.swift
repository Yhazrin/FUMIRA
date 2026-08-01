import SwiftUI

/// Clay card — lighter surface for content cards.
struct ClayCard<Content: View>: View {
    let base: Color
    let rim: Color
    let cornerRadius: CGFloat
    let content: Content

    init(
        base: Color = ClayPalette.warmWhite,
        rim: Color = ClayPalette.warmWhiteRim,
        cornerRadius: CGFloat = ClayShape.card,
        @ViewBuilder content: () -> Content
    ) {
        self.base = base
        self.rim = rim
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(ClaySpacing.cardPadding)
            .background {
                ClaySurface(
                    base: base,
                    rim: rim,
                    cornerRadius: cornerRadius,
                    shadow: ClayShadow.card
                )
            }
    }
}

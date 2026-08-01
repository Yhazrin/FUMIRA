import SwiftUI

/// Floating functional card using Apple's solid (regular) glass surface.
///
/// - iOS 26+: native ``glassEffect(_:in:)`` with the regular (frosted) variant —
///   Apple's “实色 glass”, not the clear/highly transparent media variant.
/// - iOS 17–25: ``regularMaterial`` fallback so the card still reads as system
///   glass instead of a painted flat fill.
struct PosterGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = PosterRadius.card
    /// Optional brand tint blended into the glass (e.g. ``actionBlue``).
    var tint: Color? = PosterPalette.actionBlue.opacity(0.22)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(PosterSpacing.md)
            .modifier(
                PosterGlassCardSurface(
                    cornerRadius: cornerRadius,
                    tint: tint
                )
            )
    }
}

private struct PosterGlassCardSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(iOS26Glass, in: shape)
        } else {
            content
                .background {
                    shape
                        .fill(.regularMaterial)
                    if let tint {
                        shape
                            .fill(tint.opacity(0.18))
                    }
                }
                .overlay {
                    shape
                        .stroke(PosterPalette.paperWhite.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: PosterEffects.floating, radius: 14, y: 6)
        }
    }

    @available(iOS 26.0, *)
    private var iOS26Glass: Glass {
        if let tint {
            .regular.tint(tint)
        } else {
            .regular
        }
    }
}

extension View {
    /// Apply Apple solid-glass card chrome around an already-padded surface.
    func posterGlassCardChrome(
        cornerRadius: CGFloat = PosterRadius.card,
        tint: Color? = PosterPalette.actionBlue.opacity(0.22)
    ) -> some View {
        modifier(
            PosterGlassCardSurface(
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }
}

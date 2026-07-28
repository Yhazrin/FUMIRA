import SwiftUI

/// Page-stack style: cards inside the bottom panel rise + fade in as they cross
/// the visibility threshold. Pure iOS 17 SwiftUI — no GeometryReader, no
/// PreferenceKey. Falls back to instant presentation under Reduce Motion so
/// we never double up with the existing poster transitions.
///
/// Apply directly on the row, not on the ScrollView container, because the
/// effect phases are tied to each child's scroll position.
@available(iOS 17.0, *)
extension View {
    /// Reveals the receiver with a soft lift + opacity once the row is more than
    /// ``threshold`` visible. ``threshold`` is in 0…1 of the row's height in the
    /// viewport (Apple's ``.visible`` semantics).
    func posterScrollReveal(
        threshold: Double = 0.18,
        reduceMotion: Bool = false
    ) -> some View {
        modifier(
            PosterScrollRevealModifier(
                threshold: threshold,
                reduceMotion: reduceMotion
            )
        )
    }
}

@available(iOS 17.0, *)
private struct PosterScrollRevealModifier: ViewModifier {
    var threshold: Double
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .scrollTransition(
                reduceMotion
                    ? .interactive
                    : .animated(PosterMotion.scrollReveal)
                        .threshold(.visible(threshold)),
                axis: .vertical
            ) { effect, phase in
                effect
                    .opacity(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0))
                    .scaleEffect(
                        reduceMotion
                            ? 1
                            : (phase.isIdentity ? 1 : 0.985),
                        anchor: .top
                    )
            }
    }
}

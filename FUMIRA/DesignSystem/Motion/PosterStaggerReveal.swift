import SwiftUI

/// Per-row stagger inside a List / ScrollView. iOS 17 native
/// ``scrollTransition`` does the visibility tracking; we layer a small
/// additional animation delay so rows settle into place with a touch of
/// sequential offset. Honors Reduce Motion by returning the receiver
/// unchanged.
///
/// Use on rows inside ``List { ... }`` or a ``ScrollView`` so the same
/// threshold-based effect as ``posterScrollReveal`` kicks in.
@available(iOS 17.0, *)
extension View {
    /// Stagger by ``index`` of the row in its scroll container. Earlier rows
    /// (index 0) enter immediately; later rows lag by ``step`` seconds.
    /// Cap with ``cap`` so even long lists finish staggering within 0.6s.
    func posterStaggerReveal(
        index: Int,
        step: Double = 0.06,
        cap: Double = 0.6,
        threshold: Double = 0.18,
        reduceMotion: Bool = false
    ) -> some View {
        let extraLag = reduceMotion ? 0 : min(Double(index) * step, cap)
        return modifier(
            PosterStaggerRevealModifier(
                threshold: threshold,
                extraLag: extraLag,
                reduceMotion: reduceMotion
            )
        )
    }
}

@available(iOS 17.0, *)
private struct PosterStaggerRevealModifier: ViewModifier {
    var threshold: Double
    var extraLag: Double
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        let baseAnimation: Animation = .timingCurve(
            0.22, 1, 0.36, 1,
            duration: PosterMotion.scrollRevealDuration
        )
        let animation = extraLag > 0 ? baseAnimation.delay(extraLag) : baseAnimation
        return content
            .scrollTransition(
                reduceMotion
                    ? .interactive
                    : .animated(animation).threshold(.visible(threshold)),
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

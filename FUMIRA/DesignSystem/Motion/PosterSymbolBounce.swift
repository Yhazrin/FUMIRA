import SwiftUI

/// Bounce / pulse effect on SF Symbols in step with view state. iOS 17+
/// native. Honors Reduce Motion by skipping the effect entirely.
@available(iOS 17.0, *)
extension View {
    /// Bounces the receiver every time ``trigger`` changes. Pass any
    /// Hashable that bumps when the symbol should "react" — phase ticks,
    /// completion flags, etc.
    func posterSymbolBounce<V: Hashable>(
        trigger: V,
        reduced: Bool = false
    ) -> some View {
        modifier(PosterSymbolBounceModifier(trigger: trigger, reduced: reduced))
    }
}

@available(iOS 17.0, *)
private struct PosterSymbolBounceModifier<V: Hashable>: ViewModifier {
    var trigger: V
    var reduced: Bool

    func body(content: Content) -> some View {
        if reduced {
            content
        } else {
            content.symbolEffect(.bounce, value: trigger)
        }
    }
}

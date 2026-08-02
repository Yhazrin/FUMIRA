import SwiftUI

/// Placeholder for 120fps frame rate hinting.
/// Re-enable by adding `.highFrameRate()` to interaction surfaces after
/// confirming the base flow is stable.
struct HighFrameRateModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func highFrameRate() -> some View {
        self
    }
}

import SwiftUI

/// Per-character cascade used for the FUMIRA wordmark so the brand lands as a
/// wave rather than a single chunk. The receiver is treated as one
/// "staggered index" — earlier items have zero extra lag, later items lag
/// by ``step`` up to ``cap``. Wraps the existing ``flatMotionEntrance`` so we
/// reuse the same reduced-motion handling and spring curve.
@available(iOS 17.0, *)
extension View {
    /// Stagger the receiver as the ``index``-th item in a fixed cascade. The
    /// first item has zero extra lag; later items lag by ``step`` seconds.
    func posterStaggerEntrance(
        isVisible: Bool,
        index: Int,
        step: Duration = .milliseconds(60),
        cap: Duration = .milliseconds(420),
        reduceMotion: Bool = false
    ) -> some View {
        let stepMillis = Int64(Double(step.components.seconds) * 1000)
            + Int64(step.components.attoseconds / 1_000_000_000_000_000)
        let capped = min(
            Duration.milliseconds(Int64(index) * stepMillis),
            cap
        )
        return flatMotionEntrance(
            isVisible: isVisible,
            reduceMotion: reduceMotion,
            delay: capped
        )
    }
}

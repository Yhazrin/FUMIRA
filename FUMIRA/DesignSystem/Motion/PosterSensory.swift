import SwiftUI

/// Lightweight declarative sensory feedback that fires in step with view-level
/// state changes (e.g. ``generationProgress`` crossing a threshold). It plays
/// alongside the imperative ``HapticsClient`` so the same event still produces
/// a haptic whether it was triggered by a view state or by an AppModel call.
///
/// Use only when the *view* owns the change. For action-triggered events
/// (capture, save), keep using ``dependencies.haptics.play`` in the model.
extension View {
    /// Fires ``SensoryFeedback`` when ``trigger`` changes. Pass a stable
    /// Hashable value (an enum case, an Int progress, a UUID). iOS 17+.
    func posterSensoryFeedback<V: Hashable>(
        trigger: V,
        _ feedback: SensoryFeedback
    ) -> some View {
        modifier(
            PosterSensoryFeedbackModifier(trigger: trigger, feedback: feedback)
        )
    }
}

@available(iOS 17.0, *)
private struct PosterSensoryFeedbackModifier<V: Hashable>: ViewModifier {
    var trigger: V
    var feedback: SensoryFeedback

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, _ in
            feedback
        }
    }
}

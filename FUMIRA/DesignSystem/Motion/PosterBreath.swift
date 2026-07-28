import SwiftUI

/// Page-stack-style "breath" loop: a view gently grows / shrinks at a slow
/// cadence so waiting pages never feel like a frozen spinner. Pure SwiftUI
/// spring + repeat animation, no platform-specific phase APIs. Honors Reduce
/// Motion by returning the receiver unchanged.
@available(iOS 17.0, *)
extension View {
    /// Continuous breath between the given scales. ``period`` in seconds.
    func posterBreath(
        min: Double = 0.985,
        max: Double = 1.015,
        period: Double = 1.6,
        reduceMotion: Bool = false
    ) -> some View {
        modifier(
            PosterBreathModifier(
                min: min,
                max: max,
                period: period,
                reduceMotion: reduceMotion
            )
        )
    }

    /// Shorter, more eager pulse for "starting / waiting to begin" — used by
    /// the connection feedback dot to advertise liveness without distracting.
    func posterPulse(
        period: Double = 1.05,
        reduceMotion: Bool = false
    ) -> some View {
        posterBreath(min: 0.965, max: 1.035, period: period, reduceMotion: reduceMotion)
    }
}

@available(iOS 17.0, *)
private struct PosterBreathModifier: ViewModifier {
    var min: Double
    var max: Double
    var period: Double
    var reduceMotion: Bool

    @State private var isInhaled: Bool = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .scaleEffect(
                    isInhaled ? CGFloat(max) : CGFloat(min),
                    anchor: .center
                )
                .animation(
                    .easeInOut(duration: period)
                        .repeatForever(autoreverses: true),
                    value: isInhaled
                )
                .onAppear {
                    isInhaled = true
                }
        }
    }
}

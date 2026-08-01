import SwiftUI

extension AnyTransition {
    /// Soft chrome-only phase swap. Opacity never drops to 0 so the permanent
    /// RootView backdrop cannot punch through as a white/black flash.
    static func posterPhase(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            .identity
        } else {
            .modifier(
                active: PhaseOpacityFloor(opacity: 0.96),
                identity: PhaseOpacityFloor(opacity: 1)
            )
            .combined(with: .scale(scale: 0.992))
            .combined(with: .offset(y: 4))
        }
    }

    /// Kept for call-site compatibility. Viewfinder slide is now an explicit
    /// RootView progress track (`viewfinderSlideProgress`) because AppModel
    /// phase swaps are not wrapped in `withAnimation`.
    static func cameraAperture(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .offset(y: -48)
                .combined(
                    with: .modifier(
                        active: PhaseOpacityFloor(opacity: 0.92),
                        identity: PhaseOpacityFloor(opacity: 1)
                    )
                ),
            removal: .identity
        )
    }

    /// Kept for call-site compatibility. Shutter flash is a Root overlay now —
    /// do not fade the page away with Pow snapshot / filmExposure.
    static func cameraSnapshot(reduceMotion: Bool) -> AnyTransition {
        posterPhase(reduceMotion: reduceMotion)
    }

    /// Shutter stage: identity so the persistent hero owns continuity.
    static func photoDropAway(reduceMotion: Bool) -> AnyTransition {
        .identity
    }

    /// Understanding entry: identity insert; chrome fades inside the page.
    static func photoDropIn(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .identity,
            removal: .modifier(
                active: PhaseOpacityFloor(opacity: 0.96),
                identity: PhaseOpacityFloor(opacity: 1)
            )
            .animation(PosterMotion.phaseChange)
        )
    }

    /// Result reveal: soft chrome only — hero hosts the generated image morph.
    static func generatedReveal(reduceMotion: Bool) -> AnyTransition {
        posterPhase(reduceMotion: reduceMotion)
    }
}

extension Animation {
    static func posterPhaseChange(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.phaseChange
    }

    static func posterHeroMorph(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.heroMorph
    }

    static func posterPhotoDrop(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.photoDrop
    }
}

/// Floor opacity during insertion/removal so the stage never goes fully clear.
private struct PhaseOpacityFloor: ViewModifier {
    let opacity: Double

    func body(content: Content) -> some View {
        content.opacity(opacity)
    }
}

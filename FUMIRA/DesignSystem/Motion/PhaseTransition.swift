import Pow
import SwiftUI

extension AnyTransition {
    static func posterPhase(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            .opacity.combined(with: .scale(scale: 0.99))
        }
    }

    /// Camera entry settles into place without masking the live preview.
    ///
    /// `MovingParts.iris` keeps an elliptical clip at its identity state on
    /// some iOS / Pow combinations, exposing the window's white background at
    /// the top and bottom of the viewfinder. A full-rect scale/fade preserves
    /// the sense of entering the camera while keeping every pixel available
    /// for composition.
    static func cameraAperture(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 1.015))
                .animation(PosterMotion.aperture),
            removal: .opacity.animation(PosterMotion.exitAnimation)
        )
    }

    /// A brief overexposure bridges live preview and the captured frame.
    static func cameraSnapshot(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .movingParts.snapshot.animation(PosterMotion.shutter),
            removal: .movingParts.filmExposure.animation(PosterMotion.exitAnimation)
        )
    }

    /// A vertical green exposure pass makes generation feel like film developing.
    static func generatedReveal(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .movingParts
                .glare(angle: .degrees(90), color: PosterPalette.leafGreen)
                .animation(PosterMotion.reveal),
            removal: .opacity.animation(PosterMotion.exitAnimation)
        )
    }
}

extension Animation {
    static func posterPhaseChange(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.decelerate
    }
}

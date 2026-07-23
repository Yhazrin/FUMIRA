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

    /// Camera entry behaves like opening a real aperture, without 3D chrome.
    static func cameraAperture(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .movingParts
                .iris(origin: .center, blurRadius: 2)
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

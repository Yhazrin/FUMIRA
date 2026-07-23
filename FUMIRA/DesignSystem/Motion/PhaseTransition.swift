import SwiftUI

extension AnyTransition {
    static func posterPhase(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            .opacity.combined(with: .scale(scale: 0.98))
        }
    }
}

extension Animation {
    static func posterPhaseChange(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.pageTransition
    }
}

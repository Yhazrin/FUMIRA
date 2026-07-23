import SwiftUI

enum PosterEffects {
    static let floating = Color.black.opacity(0.16)
    static let control = Color.black.opacity(0.14)
    static let cameraTopScrim = PosterPalette.ink.opacity(0.42)
    static let cameraBottomScrim = PosterPalette.ink.opacity(0.18)
    static let cameraTitleShadow = PosterPalette.ink.opacity(0.28)
    static let cameraControlSurface = PosterPalette.paper.opacity(0.95)
    static let cameraTitleShadowRadius: CGFloat = 5
    static let cameraTitleShadowOffset: CGFloat = 2
}

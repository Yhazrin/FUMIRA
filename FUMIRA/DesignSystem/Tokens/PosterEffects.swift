import SwiftUI

enum PosterEffects {
    static let floating = Color.black.opacity(0.16)
    static let control = Color.black.opacity(0.14)

    /// Immersive viewfinder: soft top/bottom scrims — never opaque cards.
    static let cameraTopScrim = PosterPalette.ink.opacity(0.38)
    static let cameraBottomScrim = PosterPalette.ink.opacity(0.48)
    static let cameraTitleShadow = PosterPalette.ink.opacity(0.28)
    /// Legacy card surface — prefer chrome circles + scrims on viewfinder.
    static let cameraControlSurface = PosterPalette.canvas.opacity(0.95)
    static let cameraTitleShadowRadius: CGFloat = 5
    static let cameraTitleShadowOffset: CGFloat = 2

    /// Translucent circular chrome for shutter-adjacent controls.
    static let cameraChromeFill = PosterPalette.ink.opacity(0.42)
    static let cameraChromeStroke = PosterPalette.paperWhite.opacity(0.28)
    static let cameraShutterRing = PosterPalette.paperWhite.opacity(0.92)
    static let cameraShutterFill = PosterPalette.paperWhite.opacity(0.88)
    static let cameraFlashWash = PosterPalette.paperWhite

    /// Adaptive composition glass tint layered over the system material.
    static let cameraCompositionLightTint = PosterPalette.paperWhite.opacity(0.10)
    static let cameraCompositionDarkTint = PosterPalette.ink.opacity(0.18)
    static let cameraCompositionStroke = PosterPalette.paperWhite.opacity(0.34)
    static let cameraShutterBodyShadow = PosterPalette.cameraShutterBlueDeep.opacity(0.42)
    static let cameraShutterFaceStroke = PosterPalette.cameraShutterBlue.opacity(0.20)
    static let cameraShutterTopHighlight = PosterPalette.paperWhite.opacity(0.30)

    static let photoPaperStroke = PosterPalette.ink.opacity(0.12)
    static let photoPaperFiber = PosterPalette.ink.opacity(0.055)
    static let photoPaperFooterMark = PosterPalette.ink.opacity(0.32)
    static let photoPaperShadow = PosterPalette.ink.opacity(0.28)
    static let photoPaperLandingShadowRadius: CGFloat = 20
    static let photoPaperLandingShadowOffset: CGFloat = 13
}

import SwiftUI

enum PosterEffects {
    static let floating = ClayShadow.rest.color
    static let control = ClayShadow.small.color
    static let cardShadow = ClayShadow.card.color
    static let cardStroke = ClayPalette.warmWhiteRim.opacity(0.72)

    /// 沉浸取景器
    static let cameraTopScrim = ClayPalette.charcoal.opacity(0.38)
    static let cameraBottomScrim = ClayPalette.charcoal.opacity(0.48)
    static let cameraTitleShadow = ClayPalette.charcoal.opacity(0.28)
    static let cameraControlSurface = ClayPalette.charcoal.opacity(0.95)
    static let cameraTitleShadowRadius: CGFloat = 5
    static let cameraTitleShadowOffset: CGFloat = 2

    /// 圆形 chrome 控件
    static let cameraChromeFill = ClayPalette.charcoal.opacity(0.42)
    static let cameraChromeStroke = ClayPalette.warmWhite.opacity(0.28)
    static let cameraActionFill = ClayPalette.orange
    static let cameraActionForeground = ClayPalette.charcoal
    static let cameraActionStroke = ClayPalette.orangeRim.opacity(0.28)

    /// 紧凑反馈
    static let cameraChromeSolidFill = ClayPalette.orangeDepth
    static let cameraChromeSolidForeground = ClayPalette.warmWhite
    static let cameraChromeSolidStroke = ClayPalette.orange.opacity(0.72)
    static let cameraChromeFeedbackShadowRadius: CGFloat = 4
    static let cameraChromeFeedbackShadowOffset: CGFloat = 2
    static let cameraShutterRing = ClayPalette.warmWhite.opacity(0.92)
    static let cameraShutterFill = ClayPalette.warmWhite.opacity(0.88)
    static let cameraFlashWash = ClayPalette.warmWhite

    /// 构图玻璃
    static let cameraCompositionLightTint = ClayPalette.warmWhite.opacity(0.10)
    static let cameraCompositionDarkTint = ClayPalette.charcoal.opacity(0.18)
    static let cameraCompositionStroke = ClayPalette.warmWhite.opacity(0.34)
    static let cameraShutterBodyShadow = ClayPalette.orangeRim.opacity(0.42)
    static let cameraShutterFaceStroke = ClayPalette.orange.opacity(0.20)
    static let cameraShutterTopHighlight = ClayPalette.warmWhite.opacity(0.30)
    static let cameraFloatingWaveShadow = ClayPalette.charcoal.opacity(0.24)
    static let cameraFloatingWaveShadowRadius: CGFloat = 10
    static let cameraFloatingWaveShadowOffset: CGFloat = 3

    /// 照片纸效果
    static let photoPaperStroke = ClayPalette.charcoal.opacity(0.12)
    static let photoPaperFiber = ClayPalette.charcoal.opacity(0.055)
    static let photoPaperFooterMark = ClayPalette.charcoal.opacity(0.32)
    static let photoPaperShadow = ClayShadow.rest.color
    static let photoPaperLandingShadowRadius: CGFloat = ClayShadow.rest.radius
    static let photoPaperLandingShadowOffset: CGFloat = ClayShadow.rest.y
}

import SwiftUI

enum PosterMotion {
    // Durations (seconds) — flat poster motion language
    static let microMin = 0.10
    static let microMax = 0.22
    static let entranceMin = 0.45
    static let entranceMax = 0.65
    static let exitFactor = 0.75

    static let micro = 0.18
    static let entrance = 0.55
    static let exit = entrance * exitFactor
    static let timeFlow = 0.34
    static let timeRailKickDuration = 0.07
    static let timeRailSettleDuration = 0.20
    /// Viewfinder aspect / composition hole morph — locked to ``heroMorphDuration``
    /// so the frost window and HeroPhotoSurface never drift apart.
    static let cameraCompositionDuration = 0.48
    /// Soft chrome-only phase swap — never the 0.55s entrance curve.
    static let phaseTransition = 0.22
    /// Persistent hero frame morph across pipeline stages (and viewfinder aspect).
    static let heroMorphDuration = 0.48
    /// Live preview → captured still crossfade inside the hero.
    static let heroCaptureCrossfade = 0.10
    /// Brief still-image dwell before the physical photo-paper handoff begins.
    static let shutterDwell = 0.18
    /// Viewfinder still → paper landing. Long enough to read, without a bounce.
    static let photoDropDuration = 0.62
    static let photoPaperUnderstandingRotation = -1.35
    static let photoPaperStoryWritingRotation = 0.7
    static let photoPaperStoryReadyRotation = -0.45
    static let photoPaperGeneratingRotation = 0.25
    /// Captured → generated crossfade inside the hero.
    static let heroGeneratedCrossfade = 0.24
    /// Independent shutter flash overlay (up + down ≤ ~120ms).
    static let shutterFlashUp = 0.025
    static let shutterFlashDown = 0.075
    static let poster = entrance
    static let page = 0.52
    static let reduced = 0.15
    static let cameraInputGuard = Duration.milliseconds(320)
    static let cameraShutterPressDownDuration = 0.055
    static let cameraShutterReleaseDuration = 0.13

    static let decelerate = Animation.timingCurve(0.22, 1, 0.36, 1, duration: entrance)
    static let interaction = Animation.timingCurve(0.33, 1, 0.68, 1, duration: micro)
    static let exitAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: exit)
    static let press = interaction
    static let flow = Animation.timingCurve(0.33, 1, 0.68, 1, duration: timeFlow)
    /// A firm, non-bouncy impulse for the physical time-wheel lock.
    static let timeRailKick = Animation.timingCurve(0.12, 0.94, 0.20, 1, duration: timeRailKickDuration)
    static let timeRailSettle = Animation.timingCurve(0.18, 0.86, 0.24, 1, duration: timeRailSettleDuration)
    /// Ratio / composition-hole morph — same curve as ``heroMorph`` so mask + hero lockstep.
    static let cameraComposition = Animation.timingCurve(0.22, 1, 0.36, 1, duration: cameraCompositionDuration)
    static let pageTransition = Animation.timingCurve(0.22, 1, 0.36, 1, duration: page)
    /// Phase chrome swap (~0.22s). Prefer over ``decelerate`` for RootView phase changes.
    static let phaseChange = Animation.timingCurve(0.22, 1, 0.36, 1, duration: phaseTransition)
    static let heroMorph = Animation.timingCurve(0.22, 1, 0.36, 1, duration: heroMorphDuration)
    static let photoDrop = Animation.timingCurve(0.16, 0.88, 0.18, 1, duration: photoDropDuration)
    static let cameraShutterPressDown = Animation.timingCurve(
        0.20,
        0.90,
        0.24,
        1,
        duration: cameraShutterPressDownDuration
    )
    static let cameraShutterRelease = Animation.timingCurve(
        0.16,
        1,
        0.30,
        1,
        duration: cameraShutterReleaseDuration
    )
    static let aperture = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.58)
    static let shutter = Animation.timingCurve(0.7, 0, 0.84, 0, duration: 0.2)
    static let reveal = Animation.timingCurve(0.12, 0.78, 0.18, 1, duration: 0.72)
}

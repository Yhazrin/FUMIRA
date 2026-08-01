import SwiftUI

enum PosterMotion {
    /// Page-stack scroll-driven fade+lift. Used by ``PosterScrollReveal`` so list
    /// sections enter when their viewport threshold is reached instead of all at once.
    static let scrollRevealDuration = 0.42
    static let scrollRevealLag = 0.08

    // Durations (seconds) — spatial poster motion language
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
    /// Viewfinder aspect-card morph. Live preview, grid, gesture surface, and
    /// wave-shutter share geometry, so one native smooth curve drives the group.
    static let cameraCompositionDuration = 0.38
    static let cameraAspectBadgeHold = Duration.milliseconds(900)
    static let cameraAspectBadgeTransitionScale: CGFloat = 0.94
    /// Keep a shutter-adjacent reality slice readable after the finger lifts.
    /// The gesture itself selects continuously; this dwell gives sighted and
    /// assistive-technology users enough time to understand the sampled instant.
    static let temporalSliceInspectionHold = Duration.milliseconds(2_200)
    /// Soft chrome-only phase swap — never the 0.55s entrance curve.
    static let phaseTransition = 0.22
    /// Persistent hero frame morph across pipeline stages.
    static let heroMorphDuration = 0.48
    /// Live preview → captured still crossfade inside the hero.
    static let heroCaptureCrossfade = 0.10
    /// Brief still-image dwell before the physical photo-paper handoff begins.
    static let shutterDwell = 0.18
    /// Viewfinder still → paper landing. Long enough to read, without a bounce.
    static let photoDropDuration = 0.62
    /// One continuous connection lens → camera portal transition.
    /// Slow enough for irregular liquid lobes to read before the field solidifies.
    static let cameraEntryDuration = 1.18
    static let cameraEntryResolveDuration = 0.28
    static let cameraEntrySourceDiameter: CGFloat = 88
    static let cameraEntryMaximumScale: CGFloat = 1.55
    /// Viewfinder card slides down from the top — Apple smooth, no bounce.
    static let cameraViewfinderSlideDuration = 0.72
    /// Flat-graphic wave-rail intro after the preview card is in motion.
    static let cameraRailIntroDuration = 0.58
    static let cameraRailIntroDelay = Duration.milliseconds(260)
    /// Capture has one principal timeline; the app may wait for the physical
    /// still image, but visual interpolation never uses separate delays.
    static let captureLiftDuration = 0.28
    static let captureSettleDuration = 0.52
    /// Semantic hold for a physical still after capture. This is not a visual
    /// timeline; RootView's `captureProgress` owns the interpolation.
    static let capturePresentationHold = 0.28
    static let timeRevealDuration = 0.62
    /// Interpolates bounded Vision updates without making the focus frame lag.
    static let subjectTrackingDuration = 0.24
    /// The photo reaches one short spatial-print apex, then returns to its
    /// resting flat pose. These are transition tracks, never idle animation.
    static let spatialPeakDuration = 0.18
    static let spatialSettleDuration = 0.40
    static let spatialPerspective: CGFloat = 0.62
    static let spatialScalePeak: CGFloat = 0.012
    static let captureSpatialPitchDegrees = 4.5
    static let captureSpatialYawDegrees = -6.0
    static let resultSpatialPitchDegrees = -4.0
    static let resultSpatialYawDegrees = 5.5
    static let resultSpatialRollDegrees = -0.65
    static let lensSpatialPitchDegrees = -2.5
    static let lensSpatialYawDegrees = 3.5
    static let photoPaperUnderstandingRotation = -1.35
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
    static let cameraShutterPressedScale: CGFloat = 0.94
    static let cameraShutterMorphDuration = 0.18
    /// Result sheet follows the finger directly, then resolves once on release.
    static let resultPanelSettleDuration = 0.28

    static let decelerate = Animation.timingCurve(0.22, 1, 0.36, 1, duration: entrance)
    static let interaction = Animation.timingCurve(0.33, 1, 0.68, 1, duration: micro)
    static let exitAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: exit)
    static let press = interaction
    static let flow = Animation.timingCurve(0.33, 1, 0.68, 1, duration: timeFlow)
    /// A firm, non-bouncy impulse for the physical time-wheel lock.
    static let timeRailKick = Animation.timingCurve(0.12, 0.94, 0.20, 1, duration: timeRailKickDuration)
    static let timeRailSettle = Animation.timingCurve(0.18, 0.86, 0.24, 1, duration: timeRailSettleDuration)
    /// Ratio / composition-card morph — native smooth, flat, and bounce-free.
    static let cameraComposition = Animation.smooth(
        duration: cameraCompositionDuration,
        extraBounce: 0
    )
    static let pageTransition = Animation.timingCurve(0.22, 1, 0.36, 1, duration: page)
    /// Phase chrome swap (~0.22s). Prefer over ``decelerate`` for RootView phase changes.
    static let phaseChange = Animation.timingCurve(0.22, 1, 0.36, 1, duration: phaseTransition)
    static let heroMorph = Animation.timingCurve(0.22, 1, 0.36, 1, duration: heroMorphDuration)
    static let photoDrop = Animation.timingCurve(0.16, 0.88, 0.18, 1, duration: photoDropDuration)
    static let spatialPeak = Animation.timingCurve(0.20, 0.90, 0.24, 1, duration: spatialPeakDuration)
    static let spatialSettle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: spatialSettleDuration)
    static let cameraEntry = Animation.timingCurve(
        0.42,
        0,
        0.58,
        1,
        duration: cameraEntryDuration
    )
    static let cameraEntryResolve = Animation.timingCurve(
        0.16,
        1,
        0.30,
        1,
        duration: cameraEntryResolveDuration
    )
    /// System-native smooth curve (iOS 17+). Matches Apple sheet / card reveals.
    static let cameraViewfinderSlide = Animation.smooth(
        duration: cameraViewfinderSlideDuration,
        extraBounce: 0
    )
    /// Crisp flat poster reveal — no bounce, geometric settle.
    static let cameraRailIntro = Animation.timingCurve(
        0.18,
        0.88,
        0.22,
        1,
        duration: cameraRailIntroDuration
    )
    static let captureLift = Animation.timingCurve(
        0.20,
        0.90,
        0.24,
        1,
        duration: captureLiftDuration
    )
    static let captureSettle = Animation.timingCurve(
        0.22,
        1,
        0.36,
        1,
        duration: captureSettleDuration
    )
    static let timeReveal = Animation.timingCurve(
        0.16,
        1,
        0.30,
        1,
        duration: timeRevealDuration
    )
    static let subjectTracking = Animation.timingCurve(
        0.22,
        1,
        0.36,
        1,
        duration: subjectTrackingDuration
    )
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
    /// Cursor ↔ time-bar conversion is a short, monotonic interpolation.
    /// It must never use a spring because the finger owns the rail position.
    static let cameraShutterMorph = Animation.timingCurve(
        0.20,
        0.90,
        0.24,
        1,
        duration: cameraShutterMorphDuration
    )
    static let resultPanelSettle = Animation.timingCurve(
        0.22,
        1,
        0.36,
        1,
        duration: resultPanelSettleDuration
    )
    static let photoHandSettle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)
    static let aperture = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.58)
    static let shutter = Animation.timingCurve(0.7, 0, 0.84, 0, duration: 0.2)
    static let reveal = Animation.timingCurve(0.12, 0.78, 0.18, 1, duration: 0.72)
    /// Soft lift for cards entering on scroll. iOS 17+ scrollTransition curve.
    static let scrollReveal = Animation.timingCurve(0.22, 1, 0.36, 1, duration: scrollRevealDuration)
}

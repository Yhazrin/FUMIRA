import SwiftUI

/// Central mapping rules for FUMIRA's restrained spatial-poster motion.
///
/// All core transitions use a single normalized value and derive their
/// sub-beats from it. This keeps geometry, lighting and chrome in the same
/// visual timeline instead of coordinating independent Boolean animations.
enum FUMIRASpatialMotion {
    static func clamp(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    static func map(
        _ progress: CGFloat,
        from inputRange: ClosedRange<CGFloat>,
        to outputRange: ClosedRange<CGFloat>
    ) -> CGFloat {
        let inputDistance = inputRange.upperBound - inputRange.lowerBound
        guard inputDistance > 0 else { return outputRange.lowerBound }

        let normalized = clamp((progress - inputRange.lowerBound) / inputDistance)
        return outputRange.lowerBound
            + (outputRange.upperBound - outputRange.lowerBound) * normalized
    }

    /// A peak that starts and ends flat. Used for a brief photo lift while the
    /// semantic transition itself continues to its resting state.
    static func spatialPulse(_ progress: CGFloat) -> CGFloat {
        sin(clamp(progress) * .pi)
    }

    /// One full card revolution on the capture timeline. The spin completes by
    /// the lift peak (`0.72`); settle (`0.72...1`) keeps the front face so the
    /// print never rests on its blank reverse during the shuttered hold.
    static func captureFlipDegrees(_ progress: CGFloat) -> Double {
        Double(map(progress, from: 0...0.72, to: 0...1)) * 360
    }

    static func captureHeroProgress(_ progress: CGFloat) -> CGFloat {
        map(progress, from: 0...0.72, to: 0...1)
    }

    static func captureChromeProgress(_ progress: CGFloat) -> CGFloat {
        map(progress, from: 0.12...0.48, to: 0...1)
    }

    static func captureTextProgress(_ progress: CGFloat) -> CGFloat {
        map(progress, from: 0.52...0.88, to: 0...1)
    }

    static func cameraPortalScale(_ progress: CGFloat, in size: CGSize) -> CGFloat {
        let minimumDimension = max(min(size.width, size.height), 1)
        let sourceScale = PosterMotion.cameraEntrySourceDiameter / minimumDimension
        return sourceScale + (PosterMotion.cameraEntryMaximumScale - sourceScale) * clamp(progress)
    }

    static func photoShadowOffset(
        lift: CGFloat,
        pitch: Double,
        yaw: Double,
        motionRoll: Double,
        motionPitch: Double
    ) -> CGSize {
        CGSize(
            width: CGFloat(-yaw / 12 - motionRoll * 3),
            height: 3 + clamp(lift) * 9 + CGFloat(pitch / 16 + motionPitch * 2)
        )
    }
}

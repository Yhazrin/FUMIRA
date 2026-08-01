import CoreGraphics
import Foundation

/// A lightweight, UI-ready subject observation in top-left normalized camera
/// coordinates. Vision stays behind the camera service boundary.
struct CameraTrackedSubject: Sendable, Equatable {
    let normalizedX: Double
    let normalizedY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double
    let confidence: Double

    init(
        normalizedX: Double,
        normalizedY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double,
        confidence: Double
    ) {
        let width = min(max(normalizedWidth, 0), 1)
        let height = min(max(normalizedHeight, 0), 1)
        self.normalizedX = min(max(normalizedX, 0), max(1 - width, 0))
        self.normalizedY = min(max(normalizedY, 0), max(1 - height, 0))
        self.normalizedWidth = width
        self.normalizedHeight = height
        self.confidence = min(max(confidence, 0), 1)
    }

    var center: CGPoint {
        CGPoint(
            x: normalizedX + normalizedWidth * 0.5,
            y: normalizedY + normalizedHeight * 0.5
        )
    }

    var normalizedBounds: CGRect {
        CGRect(
            x: normalizedX,
            y: normalizedY,
            width: normalizedWidth,
            height: normalizedHeight
        )
    }

    /// Returns a presentation region centered on the detected subject's core.
    /// Vision keeps tracking the full observation while the viewfinder draws a
    /// tighter, calmer reticle that does not imply the whole scene is selected.
    func focused(
        horizontalScale: Double,
        verticalScale: Double,
        maximumWidth: Double,
        maximumHeight: Double
    ) -> CameraTrackedSubject {
        let focusedWidth = min(
            normalizedWidth * min(max(horizontalScale, 0), 1),
            min(max(maximumWidth, 0), 1)
        )
        let focusedHeight = min(
            normalizedHeight * min(max(verticalScale, 0), 1),
            min(max(maximumHeight, 0), 1)
        )
        return CameraTrackedSubject(
            normalizedX: center.x - focusedWidth * 0.5,
            normalizedY: center.y - focusedHeight * 0.5,
            normalizedWidth: focusedWidth,
            normalizedHeight: focusedHeight,
            confidence: confidence
        )
    }

    func smoothed(toward target: CameraTrackedSubject, response: Double) -> CameraTrackedSubject {
        let amount = min(max(response, 0), 1)
        return CameraTrackedSubject(
            normalizedX: normalizedX + (target.normalizedX - normalizedX) * amount,
            normalizedY: normalizedY + (target.normalizedY - normalizedY) * amount,
            normalizedWidth: normalizedWidth
                + (target.normalizedWidth - normalizedWidth) * amount,
            normalizedHeight: normalizedHeight
                + (target.normalizedHeight - normalizedHeight) * amount,
            confidence: target.confidence
        )
    }

    /// High-frequency Vision samples need different presentation responses:
    /// retain micro movements, glide through ordinary motion, and catch up
    /// quickly when the locked subject genuinely moves or is reacquired.
    static func trackingResponse(forCenterDistance distance: Double) -> Double {
        switch abs(distance) {
        case 0.18...:
            0.72
        case 0.06...:
            0.38
        default:
            0.16
        }
    }
}

import CoreGraphics
import Foundation

/// Shared composition-frame math for the viewfinder mask and the persistent
/// hero surface. Both must resolve the same rect / corner radius for a given
/// container size and ``CameraAspectRatio``.
enum CameraCompositionGeometry {
    struct Layout: Equatable, Sendable {
        /// Maximum rounded camera card. The blue camera body remains visible
        /// behind this stage and owns the bottom control deck.
        var viewport: CGRect
        /// Cropped composition card, or `nil` when the native preview uses the
        /// full maximum card.
        var cropFrame: CGRect?
        /// Active rounded preview card (crop or maximum native card).
        var heroFrame: CGRect
        var cornerRadius: CGFloat
    }

    struct ControlPlacement: Equatable, Sendable {
        var centerY: CGFloat
        /// True when the exposed blue body is too shallow and the wave rail
        /// needs to read as chrome floating over the live preview.
        var overlaysPreview: Bool
    }

    static func layout(
        aspectRatio: CameraAspectRatio,
        in size: CGSize
    ) -> Layout {
        let viewport = captureViewport(aspectRatio: aspectRatio, in: size)
        let crop = compositionFrame(aspectRatio: aspectRatio, viewport: viewport, container: size)
        let hero = crop ?? viewport
        let radius = aspectRatio == .fullScreen
            ? CGFloat.zero
            : compositionCornerRadius(for: hero)
        return Layout(
            viewport: viewport,
            cropFrame: crop,
            heroFrame: hero,
            cornerRadius: radius
        )
    }

    /// Cropped ratios leave a blue physical-camera deck. Full screen is a
    /// distinct edge-to-edge stop whose controls float over the preview.
    static func captureViewport(
        aspectRatio: CameraAspectRatio,
        in size: CGSize
    ) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }

        if aspectRatio == .fullScreen {
            return CGRect(origin: .zero, size: size)
        }

        let topInset: CGFloat = 0
        let controlDeck = min(136, max(124, size.height * 0.15))
        let cardHeight = size.height - controlDeck
        return CGRect(
            x: 0,
            y: topInset,
            width: size.width,
            height: max(0, cardHeight)
        )
    }

    static func compositionFrame(
        aspectRatio: CameraAspectRatio,
        viewport: CGRect,
        container: CGSize
    ) -> CGRect? {
        guard let ratio = aspectRatio.targetAspectRatio(for: container) else { return nil }
        guard viewport.width > 0, viewport.height > 0 else { return nil }

        let availableRatio = viewport.width / viewport.height
        let frameSize: CGSize
        // Treat sub-pixel equality as full width. Without the tolerance, the
        // portrait 9:16 card can inherit a microscopic side gap after the
        // width → height → width floating-point round trip.
        if availableRatio > ratio + 0.0001 {
            frameSize = CGSize(width: viewport.height * ratio, height: viewport.height)
        } else {
            frameSize = CGSize(width: viewport.width, height: viewport.width / ratio)
        }

        // The top edge never moves. Aspect changes read as the card's lower
        // edge being physically pushed upward, exposing more of the blue body.
        return CGRect(
            x: (container.width - frameSize.width) * 0.5,
            y: viewport.minY,
            width: frameSize.width,
            height: frameSize.height
        )
    }

    static func compositionCornerRadius(for frame: CGRect) -> CGFloat {
        min(36, max(26, min(frame.width, frame.height) * 0.085))
    }

    /// Places the wave-shutter in the optical center of the exposed blue body
    /// when that deck can hold the rail. Full screen (and any ratio that leaves
    /// almost no blue) floats the same control above the home indicator.
    static func controlPlacement(
        below compositionFrame: CGRect,
        in size: CGSize,
        bottomSafeAreaInset: CGFloat
    ) -> ControlPlacement {
        let controlHeight = CameraChromeMetrics.waveRailHeight
        let safeDeckBottom = size.height
            - max(bottomSafeAreaInset + PosterSpacing.sm, PosterSpacing.xl)
        // Measure the full blue body to the screen edge. 16:9 already exposes
        // enough deck to host the rail; only compare against the rail height
        // itself, not an extra padding cushion that forced a false float.
        let visualExposedHeight = size.height - compositionFrame.maxY
        let overlaysPreview = visualExposedHeight < controlHeight

        let overlayCenter = safeDeckBottom - controlHeight * 0.5
        let rawExposedCenter = (compositionFrame.maxY + size.height) * 0.5
            + Self.waveOpticalCenterBias
        // Keep the rail inside the blue deck so a shallow-but-usable body
        // (portrait 16:9) still reads as centered, never clipped into the card.
        let minExposedCenter = compositionFrame.maxY + controlHeight * 0.5
        let maxExposedCenter = size.height - controlHeight * 0.5
        let exposedCenter = min(
            max(rawExposedCenter, minExposedCenter),
            max(maxExposedCenter, minExposedCenter)
        )

        return ControlPlacement(
            centerY: overlaysPreview ? overlayCenter : exposedCenter,
            overlaysPreview: overlaysPreview
        )
    }

    /// The shutter sits above the rail frame's geometric mid (stage then year
    /// capsule). Bias the placement down so the shutter reads as centered.
    private static var waveOpticalCenterBias: CGFloat {
        let shutterFromTop = CameraChromeMetrics.waveRailStageHeight * 0.58
        let frameMidFromTop = CameraChromeMetrics.waveRailHeight * 0.5
        return frameMidFromTop - shutterFromTop
    }

    static func controlDeckCenterY(
        below compositionFrame: CGRect,
        in size: CGSize,
        bottomSafeAreaInset: CGFloat
    ) -> CGFloat {
        controlPlacement(
            below: compositionFrame,
            in: size,
            bottomSafeAreaInset: bottomSafeAreaInset
        ).centerY
    }
}

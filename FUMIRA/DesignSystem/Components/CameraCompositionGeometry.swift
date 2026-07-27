import CoreGraphics
import Foundation

/// Shared composition-frame math for the viewfinder mask and the persistent
/// hero surface. Both must resolve the same rect / corner radius for a given
/// container size and ``CameraAspectRatio``.
enum CameraCompositionGeometry {
    struct Layout: Equatable, Sendable {
        /// Full capture viewport (middle band between chrome gutters).
        var viewport: CGRect
        /// Cropped composition frame inside the viewport, or `nil` for full-screen.
        var cropFrame: CGRect?
        /// Active photo frame the hero should occupy (crop or full viewport).
        var heroFrame: CGRect
        var cornerRadius: CGFloat
    }

    static func layout(
        aspectRatio: CameraAspectRatio,
        in size: CGSize
    ) -> Layout {
        let viewport = captureViewport(aspectRatio: aspectRatio, in: size)
        let crop = compositionFrame(aspectRatio: aspectRatio, viewport: viewport, container: size)
        let hero = crop ?? CGRect(origin: .zero, size: size)
        let radius: CGFloat
        if crop != nil {
            radius = compositionCornerRadius(for: hero)
        } else {
            radius = 0
        }
        return Layout(
            viewport: viewport,
            cropFrame: crop,
            heroFrame: hero,
            cornerRadius: radius
        )
    }

    /// Shared middle band. Classic / square keep side gutters; chrome may float
    /// over frost at the bottom so we never carve a dead rectangular dock.
    static func captureViewport(
        aspectRatio: CameraAspectRatio,
        in size: CGSize
    ) -> CGRect {
        if aspectRatio == .fullScreen {
            return CGRect(origin: .zero, size: size)
        }
        let topInset = min(92, size.height * 0.12)
        let bottomInset = min(156, size.height * 0.19)
        let gutter = sideGutter(aspectRatio: aspectRatio, in: size)
        return CGRect(
            x: gutter,
            y: topInset,
            width: max(0, size.width - gutter * 2),
            height: max(0, size.height - topInset - bottomInset)
        )
    }

    static func sideGutter(
        aspectRatio: CameraAspectRatio,
        in size: CGSize
    ) -> CGFloat {
        switch aspectRatio {
        case .fullScreen, .widescreen:
            return 0
        case .classic, .square:
            return max(12, min(20, size.width * 0.04))
        }
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
        if availableRatio > ratio {
            frameSize = CGSize(width: viewport.height * ratio, height: viewport.height)
        } else {
            frameSize = CGSize(width: viewport.width, height: viewport.width / ratio)
        }

        // Horizontal: always center in the full container so left/right margins
        // stay equal (never inherit a one-sided origin from viewport / gutters).
        // Vertical: stay centered inside the chrome viewport band.
        return CGRect(
            x: (container.width - frameSize.width) * 0.5,
            y: viewport.midY - frameSize.height * 0.5,
            width: frameSize.width,
            height: frameSize.height
        )
    }

    static func compositionCornerRadius(for frame: CGRect) -> CGFloat {
        min(34, max(24, min(frame.width, frame.height) * 0.08))
    }
}

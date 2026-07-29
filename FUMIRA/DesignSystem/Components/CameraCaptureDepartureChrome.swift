import SwiftUI

/// A non-interactive afterimage of the viewfinder chrome. It lets controls
/// leave behind the lifted photo instead of being destroyed on the shutter
/// phase boundary.
struct CameraCaptureDepartureChrome: View {
    let progress: CGFloat
    let reduceMotion: Bool
    let aspectRatio: CameraAspectRatio
    let selectedTimeNormalized: Double

    private var departure: CGFloat {
        reduceMotion ? 1 : FUMIRASpatialMotion.captureChromeProgress(progress)
    }

    var body: some View {
        GeometryReader { proxy in
            let systemInsets = CameraChromeMetrics.activeWindowSafeAreaInsets
            let compositionFrame = CameraCompositionGeometry.layout(
                aspectRatio: aspectRatio,
                in: proxy.size
            ).heroFrame
            let controlPlacement = CameraCompositionGeometry.controlPlacement(
                below: compositionFrame,
                in: proxy.size,
                bottomSafeAreaInset: systemInsets.bottom
            )

            ZStack {
                HStack {
                    CameraChromeGlyph(systemImage: "photo.on.rectangle")
                    Spacer(minLength: 0)
                    CameraChromeGlyph(
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
                .padding(.horizontal, PosterSpacing.md)
                .frame(
                    width: compositionFrame.width,
                    height: CameraChromeMetrics.topRowHeight
                )
                .position(
                    x: compositionFrame.midX,
                    y: systemInsets.top
                        + PosterSpacing.sm
                        + CameraChromeMetrics.topRowHeight * 0.5
                )

                ShutterWaveTimeRail(
                    value: selectedTimeNormalized,
                    onChange: { _ in },
                    onCapture: {}
                )
                .frame(width: proxy.size.width - PosterSpacing.md * 2)
                .position(
                    x: proxy.size.width * 0.5,
                    y: controlPlacement.centerY
                )
                .shadow(
                    color: controlPlacement.overlaysPreview
                        ? PosterEffects.cameraFloatingWaveShadow
                        : .clear,
                    radius: PosterEffects.cameraFloatingWaveShadowRadius,
                    y: PosterEffects.cameraFloatingWaveShadowOffset
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(1 - departure)
            .offset(y: -departure * 16)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

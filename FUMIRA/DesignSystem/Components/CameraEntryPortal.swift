import SwiftUI

/// A short acknowledgement of the connection-screen camera control.
///
/// This deliberately animates only the object the user touched. It never
/// expands an arbitrary background image into a full-screen circle: that
/// created exposed white clipping edges while the permission screen appeared.
struct CameraEntryPortal: View {
    let progress: CGFloat
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let clamped = FUMIRASpatialMotion.clamp(progress)
            let scale = 1 + 0.46 * clamped
            let center = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.46)

            Image(systemName: "camera.aperture")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(PosterPalette.paperWhite)
                .frame(width: PosterMotion.cameraEntrySourceDiameter, height: PosterMotion.cameraEntrySourceDiameter)
                .background(PosterPalette.actionBlueDeep)
                .clipShape(Circle())
                .scaleEffect(reduceMotion ? 1 : scale)
                .position(center)
                .opacity(
                    1 - FUMIRASpatialMotion.map(
                        clamped,
                        from: 0.38...0.82,
                        to: 0...1
                    )
                )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

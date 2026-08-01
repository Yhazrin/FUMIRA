import SwiftUI

/// Connection → camera handoff: the touched blue aperture grows into a
/// full-bleed field. A continuous primary disc owns coverage; irregular lobes
/// only soften the edge so the fill never pops from a late solidify beat.
struct CameraEntryPortal: View {
    let progress: CGFloat
    let reduceMotion: Bool

    private static let blobs: [LiquidBlob] = [
        LiquidBlob(angle: 0.18, delay: 0.00, travel: 0.18, growth: 0.55, size: 0.92),
        LiquidBlob(angle: -0.72, delay: 0.06, travel: 0.42, growth: 0.48, size: 0.70),
        LiquidBlob(angle: 1.85, delay: 0.10, travel: 0.50, growth: 0.46, size: 0.64),
        LiquidBlob(angle: 3.40, delay: 0.14, travel: 0.56, growth: 0.52, size: 0.74),
        LiquidBlob(angle: 4.55, delay: 0.18, travel: 0.38, growth: 0.42, size: 0.56),
        LiquidBlob(angle: 5.80, delay: 0.12, travel: 0.60, growth: 0.44, size: 0.60),
    ]

    var body: some View {
        GeometryReader { proxy in
            let clamped = FUMIRASpatialMotion.clamp(progress)
            let center = CGPoint(
                x: proxy.size.width * 0.5,
                y: proxy.size.height * 0.46
            )
            // Cover the farthest corner with a small margin — continuous growth
            // from the launch diameter, no late “snap fill”.
            let coverRadius = hypot(proxy.size.width, proxy.size.height) * 0.58
            let source = PosterMotion.cameraEntrySourceDiameter
            let coverScale = (coverRadius * 2) / source
            // Keep the first part visibly attached to the 88pt source before
            // acceleration takes over. The old ease-out here compounded the
            // timeline's own fast curve, so a user could perceive a large disc
            // before seeing it grow.
            let expand = CameraEntryPortalGeometry.expansionProgress(for: clamped)
            let liquidBlur = max(2.0, 22 * (1 - FUMIRASpatialMotion.map(clamped, from: 0.35...0.88, to: 0...1)))
            let iconFade = FUMIRASpatialMotion.map(clamped, from: 0.02...0.22, to: 0...1)
            let lobeOpacity = 1 - FUMIRASpatialMotion.map(clamped, from: 0.55...0.92, to: 0...1)

            ZStack {
                // Primary disc — the continuous object the user touched.
                Circle()
                    .fill(PosterPalette.actionBlue)
                    .frame(width: source, height: source)
                    .scaleEffect(reduceMotion ? coverScale : 1 + (coverScale - 1) * expand)
                    .position(center)

                // Soft irregular lobes ride the same expansion; they never own
                // the cover so alpha-threshold merge cannot flash the screen.
                Canvas { context, _ in
                    context.addFilter(
                        .alphaThreshold(min: 0.5, color: PosterPalette.actionBlue)
                    )
                    context.addFilter(.blur(radius: liquidBlur))

                    context.drawLayer { layer in
                        for (index, blob) in Self.blobs.enumerated() {
                            guard let symbol = layer.resolveSymbol(id: index) else {
                                continue
                            }
                            let local = blob.localProgress(clamped)
                            let distance = coverRadius * blob.travel * local * expand
                            let point = CGPoint(
                                x: center.x + CGFloat(cos(blob.angle)) * distance,
                                y: center.y + CGFloat(sin(blob.angle)) * distance
                            )
                            layer.draw(symbol, at: point)
                        }
                    }
                } symbols: {
                    ForEach(Array(Self.blobs.enumerated()), id: \.offset) { index, blob in
                        let local = blob.localProgress(clamped)
                        let scale = 1 + (coverScale * blob.growth - 1) * local * expand
                        liquidDisc(scale: max(scale * blob.size, 0.01))
                            .tag(index)
                    }
                }
                .opacity(reduceMotion ? 0 : lobeOpacity)
                .allowsHitTesting(false)

                Image(systemName: "camera.aperture")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .frame(width: source, height: source)
                    .scaleEffect(
                        reduceMotion
                            ? 1
                            : 1 + 0.06 * FUMIRASpatialMotion.map(clamped, from: 0...0.25, to: 0...1)
                    )
                    .position(center)
                    .opacity(1 - iconFade)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func liquidDisc(scale: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .frame(
                width: PosterMotion.cameraEntrySourceDiameter,
                height: PosterMotion.cameraEntrySourceDiameter
            )
            .scaleEffect(scale)
    }
}

/// Pure geometry for the connection aperture. A slow start makes the source
/// button legible; the latter half still reaches every corner without a pause.
enum CameraEntryPortalGeometry {
    static func expansionProgress(for timelineProgress: CGFloat) -> CGFloat {
        let normalized = FUMIRASpatialMotion.map(
            timelineProgress,
            from: 0.18...1,
            to: 0...1
        )
        return pow(normalized, 2.1)
    }
}

private struct LiquidBlob {
    let angle: Double
    let delay: CGFloat
    let travel: CGFloat
    let growth: CGFloat
    let size: CGFloat

    func localProgress(_ global: CGFloat) -> CGFloat {
        let span = max(1 - delay, 0.001)
        let raw = FUMIRASpatialMotion.clamp((global - delay) / span)
        return 1 - pow(1 - raw, 1.85)
    }
}

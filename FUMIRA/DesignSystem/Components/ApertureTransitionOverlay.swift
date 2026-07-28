import SwiftUI

/// Eight overlapping shutter blades that can seal the full viewport.
///
/// `progress == 0` keeps a wide central opening. `progress == 1` closes the
/// aperture completely, allowing RootView to swap phases behind the sealed iris.
struct ApertureBladeField: View {
    var progress: CGFloat
    var bladeCount: Int = 8
    var tint: Color = PosterPalette.actionBlueDeep
    var center: UnitPoint = .center

    var body: some View {
        Canvas { context, size in
            let clampedProgress = min(max(progress, 0), 1)
            let apertureCenter = CGPoint(
                x: size.width * center.x,
                y: size.height * center.y
            )
            let side = min(size.width, size.height)
            let outerRadius = maximumCornerDistance(
                from: apertureCenter,
                in: size
            ) + 32
            let openingRadius = outerRadius
                * pow(1 - clampedProgress, 0.72)
            let step = (CGFloat.pi * 2) / CGFloat(max(bladeCount, 3))
            let twist = step * clampedProgress * 0.58

            for blade in 0..<max(bladeCount, 3) {
                let angle = CGFloat(blade) * step - .pi / 2 + twist
                var path = Path()
                path.move(
                    to: point(
                        center: apertureCenter,
                        radius: openingRadius,
                        angle: angle
                    )
                )
                path.addCurve(
                    to: point(
                        center: apertureCenter,
                        radius: outerRadius,
                        angle: angle + step * 0.22
                    ),
                    control1: point(
                        center: apertureCenter,
                        radius: max(openingRadius, side * 0.08),
                        angle: angle + step * 0.16
                    ),
                    control2: point(
                        center: apertureCenter,
                        radius: outerRadius * 0.72,
                        angle: angle - step * 0.05
                    )
                )
                path.addLine(
                    to: point(
                        center: apertureCenter,
                        radius: outerRadius,
                        angle: angle + step * 1.24
                    )
                )
                path.addCurve(
                    to: point(
                        center: apertureCenter,
                        radius: openingRadius,
                        angle: angle + step
                    ),
                    control1: point(
                        center: apertureCenter,
                        radius: outerRadius * 0.64,
                        angle: angle + step * 1.02
                    ),
                    control2: point(
                        center: apertureCenter,
                        radius: max(openingRadius, side * 0.05),
                        angle: angle + step * 0.86
                    )
                )
                path.closeSubpath()

                let shade = 0.88 + Double(blade % 3) * 0.04
                context.fill(path, with: .color(tint.opacity(shade)))
            }

            if clampedProgress > 0.97 {
                let sealRadius = max(2, side * (clampedProgress - 0.97) * 0.3)
                let seal = Path(
                    ellipseIn: CGRect(
                        x: apertureCenter.x - sealRadius,
                        y: apertureCenter.y - sealRadius,
                        width: sealRadius * 2,
                        height: sealRadius * 2
                    )
                )
                context.fill(seal, with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }

    private func maximumCornerDistance(
        from center: CGPoint,
        in size: CGSize
    ) -> CGFloat {
        [
            hypot(center.x, center.y),
            hypot(size.width - center.x, center.y),
            hypot(center.x, size.height - center.y),
            hypot(size.width - center.x, size.height - center.y)
        ]
        .max() ?? 0
    }

    private func point(
        center: CGPoint,
        radius: CGFloat,
        angle: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

struct CameraIrisTransitionOverlay: View {
    var progress: CGFloat
    var center: UnitPoint = .center

    var body: some View {
        ApertureBladeField(
            progress: progress,
            tint: PosterPalette.actionBlueDeep,
            center: center
        )
        .accessibilityHidden(true)
    }
}

#Preview("Aperture") {
    CameraIrisTransitionOverlay(progress: 0.72)
        .ignoresSafeArea()
}

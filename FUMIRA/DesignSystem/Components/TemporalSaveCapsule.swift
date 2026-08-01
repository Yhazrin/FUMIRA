import SwiftUI

/// Result-only primary action. Its small colour field is driven by the same
/// reveal progress as the generated photo, then becomes completely still.
/// This keeps colour as a brief developing material instead of a decorative
/// full-screen gradient.
struct TemporalSaveCapsule: View {
    let title: String
    let revealProgress: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var progress: CGFloat {
        FUMIRASpatialMotion.clamp(revealProgress)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: PosterSpacing.md) {
                VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                    Text(title)
                        .font(PosterTypography.button)
                        .foregroundStyle(PosterPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("FUMIRA")
                            .font(PosterTypography.caption)
                            .foregroundStyle(PosterPalette.mutedInk)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: PosterSpacing.sm)

                TemporalTimeBlueMist(progress: progress, reduceMotion: reduceMotion)
                    .frame(
                        width: PosterSpacing.xl * (dynamicTypeSize.isAccessibilitySize ? 3 : 4),
                        height: PosterSpacing.lg + PosterSpacing.xl
                    )
                    .accessibilityHidden(true)
            }
            .padding(.leading, PosterSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PosterSpacing.lg + PosterSpacing.xl)
            .background(PosterPalette.cardLight, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(PosterPalette.line, lineWidth: 1)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PosterCapsulePressStyle())
        .accessibilityLabel(title)
        .accessibilityHint("打开海报预览，可保存到相册或系统分享")
    }
}

private struct TemporalTimeBlueMist: View {
    let progress: CGFloat
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let settledProgress = reduceMotion ? CGFloat(1) : eased(progress)
            let energyCenter = CGPoint(
                x: width * (1.02 + (1 - settledProgress) * 0.06),
                y: height * 0.5
            )
            let reach = width * (0.86 + (1 - settledProgress) * 0.05)

            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                context.drawLayer { atmosphere in
                    atmosphere.addFilter(.blur(radius: height * 0.12))
                    drawBlueAtmosphere(
                        in: &atmosphere,
                        width: width,
                        height: height,
                        center: energyCenter,
                        reach: reach
                    )
                }

                context.drawLayer { frost in
                    frost.addFilter(.blur(radius: max(height * 0.014, 0.5)))
                    drawFrostTexture(
                        in: &frost,
                        width: width,
                        height: height
                    )
                }
            }
            .frame(width: width, height: height)
            .opacity(reduceMotion ? 1 : 0.70 + settledProgress * 0.30)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.06), location: 0.18),
                        .init(color: .black.opacity(0.34), location: 0.46),
                        .init(color: .black.opacity(0.82), location: 0.72),
                        .init(color: .black, location: 0.90)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .clipped()
    }

    private func eased(_ value: CGFloat) -> CGFloat {
        let clamped = FUMIRASpatialMotion.clamp(value)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func drawBlueAtmosphere(
        in context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        center: CGPoint,
        reach: CGFloat
    ) {
        var field = Path()
        field.addRect(
            CGRect(
                x: width * 0.08,
                y: -height * 0.24,
                width: width * 1.08,
                height: height * 1.48
            )
        )

        context.fill(
            field,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: PosterPalette.timeBlue.opacity(0.96), location: 0),
                    .init(color: PosterPalette.timeBlue.opacity(0.90), location: 0.22),
                    .init(color: PosterPalette.timeBlue.opacity(0.68), location: 0.48),
                    .init(color: PosterPalette.timeBlue.opacity(0.30), location: 0.72),
                    .init(color: PosterPalette.timeBlue.opacity(0.08), location: 0.88),
                    .init(color: PosterPalette.timeBlue.opacity(0), location: 1)
                ]),
                center: center,
                startRadius: 0,
                endRadius: reach
            )
        )

        let upperCloud = CGRect(
            x: width * 0.48,
            y: -height * 0.18,
            width: width * 0.72,
            height: height * 0.94
        )
        context.fill(
            Path(ellipseIn: upperCloud),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: PosterPalette.timeBlue.opacity(0.50), location: 0),
                    .init(color: PosterPalette.timeBlue.opacity(0.28), location: 0.54),
                    .init(color: PosterPalette.timeBlue.opacity(0), location: 1)
                ]),
                center: CGPoint(x: width * 0.94, y: height * 0.22),
                startRadius: 0,
                endRadius: width * 0.50
            )
        )

        let lowerCloud = CGRect(
            x: width * 0.38,
            y: height * 0.34,
            width: width * 0.84,
            height: height * 0.98
        )
        context.fill(
            Path(ellipseIn: lowerCloud),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: PosterPalette.timeBlue.opacity(0.42), location: 0),
                    .init(color: PosterPalette.timeBlue.opacity(0.20), location: 0.58),
                    .init(color: PosterPalette.timeBlue.opacity(0), location: 1)
                ]),
                center: CGPoint(x: width * 0.92, y: height * 0.72),
                startRadius: 0,
                endRadius: width * 0.56
            )
        )
    }

    private func drawFrostTexture(
        in context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat
    ) {
        for seed in 0..<40 {
            let x = width * (0.38 + unitNoise(seed * 13 + 3) * 0.66)
            let y = height * (0.02 + unitNoise(seed * 29 + 11) * 0.96)
            let size = height * (0.018 + unitNoise(seed * 17 + 19) * 0.045)
            let normalizedX = min(max(x / width, 0), 1)
            let concentration = normalizedX * normalizedX
            let speck = CGRect(
                x: x - size * 0.5,
                y: y - size * 0.5,
                width: size,
                height: size
            )

            context.fill(
                Path(ellipseIn: speck),
                with: .color(
                    PosterPalette.timeBlue.opacity(
                        Double(0.03 + concentration * 0.11)
                    )
                )
            )
        }
    }

    private func unitNoise(_ seed: Int) -> CGFloat {
        CGFloat((seed &* 37 &+ 17) % 101) / 100
    }
}

#Preview("Temporal save capsule") {
    TemporalSaveCapsule(
        title: "保存海报",
        revealProgress: 1,
        reduceMotion: false,
        action: {}
    )
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

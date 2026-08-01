import SwiftUI
import UIKit

/// A transparent reveal layer that sits above an already-rendered target photo.
///
/// The host supplies the original photo plus normalized breath values. This
/// view never owns a timer or sensor: its paper pose, edge curl, particles and
/// target label all derive from the same `progress` and `gust` values.
struct TemporalBlowRevealSurface: View {
    let original: UIImage?
    let progress: CGFloat
    let gust: CGFloat
    let reduceMotion: Bool
    let targetLabel: String
    var handwrittenTitle: String? = nil

    private var presentation: TemporalBlowRevealPresentation {
        .resolve(
            progress: progress,
            gust: gust,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .bottomLeading) {
                originalPaper(in: size)

                if presentation.showsParticles {
                    TemporalBlowParticleField(presentation: presentation)
                        .accessibilityHidden(true)
                }

                revealLabel
            }
            .frame(width: size.width, height: size.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: PosterRadius.photoPaper,
                    style: .continuous
                )
            )
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("吹气揭幕")
        .accessibilityValue(
            "目标时间：\(targetLabel)，已揭开 \(presentation.revealedPercentage)%"
        )
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("result.blow-reveal")
    }

    private func originalPaper(in size: CGSize) -> some View {
        originalPhoto
            .frame(width: size.width, height: size.height)
            .mask {
                TemporalBlowPaperMask(
                    remainingFraction: presentation.remainingFraction,
                    curl: presentation.edgeCurl
                )
            }
            .rotation3DEffect(
                .degrees(presentation.paperBendDegrees),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: PosterMotion.spatialPerspective
            )
            .offset(y: -presentation.paperLift)
            .opacity(presentation.originalOpacity)
            .shadow(
                color: PosterEffects.photoPaperShadow.opacity(
                    presentation.paperShadowOpacity
                ),
                radius: PosterSpacing.sm,
                y: PosterSpacing.xs
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var originalPhoto: some View {
        if let original {
            Image(uiImage: original)
                .resizable()
                .scaledToFill()
        } else {
            PosterPalette.paper
                .overlay {
                    Image(systemName: "photo")
                        .font(PosterTypography.cardTitle)
                        .foregroundStyle(PosterPalette.mutedInk)
                }
        }
    }

    private var revealLabel: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            if let handwrittenTitle,
               !handwrittenTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(handwrittenTitle)
                    .font(PosterTypography.script(PosterSpacing.xl))
            }

            Text(targetLabel)
                .font(PosterTypography.label)
        }
        .foregroundStyle(PosterPalette.paperWhite)
        .shadow(
            color: PosterPalette.ink.opacity(0.42),
            radius: PosterSpacing.xs,
            y: PosterRadius.waveBar
        )
        .padding(PosterSpacing.md)
        .opacity(presentation.targetLabelOpacity)
        .accessibilityHidden(true)
    }
}

/// Pure visual mapping for previews and focused tests.
struct TemporalBlowRevealPresentation: Equatable {
    let progress: CGFloat
    let gust: CGFloat
    let remainingFraction: CGFloat
    let paperLift: CGFloat
    let paperBendDegrees: Double
    let edgeCurl: CGFloat
    let particleIntensity: CGFloat
    let originalOpacity: Double
    let targetLabelOpacity: Double
    let paperShadowOpacity: Double
    let reduceMotion: Bool

    var showsParticles: Bool {
        !reduceMotion && particleIntensity > 0
    }

    var revealedPercentage: Int {
        Int((progress * 100).rounded())
    }

    static func resolve(
        progress: CGFloat,
        gust: CGFloat,
        reduceMotion: Bool
    ) -> Self {
        let boundedProgress = bounded(progress)
        let boundedGust = bounded(gust)
        let pulse = sin(boundedProgress * .pi)
        let windStrength = boundedGust * pulse
        let completionFade = 1 - mapped(
            boundedProgress,
            from: TemporalBlowRevealMetrics.particleFadeRange
        )
        let particleIntensity = reduceMotion
            ? CGFloat.zero
            : windStrength * completionFade

        return Self(
            progress: boundedProgress,
            gust: boundedGust,
            remainingFraction: 1 - boundedProgress,
            paperLift: reduceMotion
                ? 0
                : PosterSpacing.lg * windStrength,
            paperBendDegrees: reduceMotion
                ? 0
                : -TemporalBlowRevealMetrics.maximumPaperBendDegrees
                    * Double(windStrength),
            edgeCurl: reduceMotion
                ? 0
                : PosterSpacing.sm * windStrength,
            particleIntensity: particleIntensity,
            originalOpacity: reduceMotion
                ? Double(1 - boundedProgress)
                : Double(completionFade),
            targetLabelOpacity: Double(
                mapped(
                    boundedProgress,
                    from: TemporalBlowRevealMetrics.labelRevealRange
                )
            ),
            paperShadowOpacity: reduceMotion
                ? 0
                : Double(windStrength) * TemporalBlowRevealMetrics.maximumShadowOpacity,
            reduceMotion: reduceMotion
        )
    }

    private static func bounded(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func mapped(
        _ value: CGFloat,
        from range: ClosedRange<CGFloat>
    ) -> CGFloat {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return 0 }
        return bounded((value - range.lowerBound) / distance)
    }
}

private enum TemporalBlowRevealMetrics {
    static let maximumPaperBendDegrees = 11.0
    static let maximumShadowOpacity = 0.72
    static let labelRevealRange: ClosedRange<CGFloat> = 0.42...0.76
    static let particleFadeRange: ClosedRange<CGFloat> = 0.82...1
    static let particleCount = 18
}

/// The original paper remains mounted while its lower edge travels upward.
/// A shallow central curl makes the edge react to breath without a shader.
private struct TemporalBlowPaperMask: Shape {
    var remainingFraction: CGFloat
    var curl: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(remainingFraction, curl) }
        set {
            remainingFraction = newValue.first
            curl = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let remainingHeight = rect.height * min(max(remainingFraction, 0), 1)
        guard remainingHeight > 0 else { return Path() }

        let boundedCurl = min(max(curl, 0), remainingHeight * 0.72)
        let middleY = max(remainingHeight - boundedCurl, 0)
        var path = Path()
        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: remainingHeight))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: middleY),
            control1: CGPoint(x: rect.maxX * 0.82, y: remainingHeight),
            control2: CGPoint(x: rect.maxX * 0.68, y: middleY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: remainingHeight),
            control1: CGPoint(x: rect.maxX * 0.32, y: middleY),
            control2: CGPoint(x: rect.maxX * 0.18, y: remainingHeight)
        )
        path.closeSubpath()
        return path
    }
}

/// A small deterministic paper-fleck field. It follows the moving lower edge
/// and uses only flat palette colours, so the target photo remains the hero.
private struct TemporalBlowParticleField: View {
    let presentation: TemporalBlowRevealPresentation

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let edgeY = size.height * presentation.remainingFraction
            let intensity = presentation.particleIntensity

            for index in 0..<TemporalBlowRevealMetrics.particleCount {
                let horizontalSeed = unitSeed(index, salt: 11)
                let travelSeed = unitSeed(index, salt: 37)
                let scatterSeed = unitSeed(index, salt: 71) - 0.5
                let sizeSeed = unitSeed(index, salt: 97)
                let sourceX = size.width * (0.06 + horizontalSeed * 0.88)
                let upwardTravel = size.height
                    * (0.05 + travelSeed * 0.22)
                    * intensity
                let outwardTravel = scatterSeed * size.width * 0.24 * intensity
                let fleckWidth = max(
                    PosterRadius.waveBar,
                    PosterRadius.waveBar + sizeSeed * PosterSpacing.xs
                )
                let fleckHeight = max(
                    PosterRadius.waveBar,
                    fleckWidth * (0.38 + travelSeed * 0.34)
                )
                let rect = CGRect(
                    x: sourceX + outwardTravel - fleckWidth / 2,
                    y: edgeY - upwardTravel - fleckHeight / 2,
                    width: fleckWidth,
                    height: fleckHeight
                )
                var fleck = Path()
                fleck.addRoundedRect(
                    in: rect,
                    cornerSize: CGSize(
                        width: PosterRadius.waveBar,
                        height: PosterRadius.waveBar
                    )
                )
                context.fill(
                    fleck,
                    with: .color(
                        particleColor(at: index).opacity(
                            Double(intensity) * (0.36 + Double(travelSeed) * 0.54)
                        )
                    )
                )
            }
        }
    }

    private func unitSeed(_ index: Int, salt: Int) -> CGFloat {
        let mixed = (index * 47 + salt * 29) % 101
        return CGFloat(mixed) / 100
    }

    private func particleColor(at index: Int) -> Color {
        switch index % 6 {
        case 0:
            PosterPalette.bellYellow
        case 1:
            PosterPalette.skySoft
        default:
            PosterPalette.paperWhite
        }
    }
}

#Preview("Blow reveal") {
    ZStack {
        PosterPalette.sky
            .overlay {
                Text("目标照片")
                    .font(PosterTypography.cardTitle)
                    .foregroundStyle(PosterPalette.ink)
            }

        TemporalBlowRevealSurface(
            original: nil,
            progress: 0.56,
            gust: 0.82,
            reduceMotion: false,
            targetLabel: "8.5 年后",
            handwrittenTitle: "风把此刻吹开"
        )
    }
    .aspectRatio(3.0 / 4.0, contentMode: .fit)
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

#Preview("Blow reveal — Reduce Motion") {
    ZStack {
        PosterPalette.sky

        TemporalBlowRevealSurface(
            original: nil,
            progress: 0.56,
            gust: 1,
            reduceMotion: true,
            targetLabel: "8.5 年后"
        )
    }
    .aspectRatio(3.0 / 4.0, contentMode: .fit)
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

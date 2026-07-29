import SwiftUI
import UIKit

/// Direct-manipulation pose for an already-captured print. It is intentionally
/// bounded: the photograph feels held in the hand, never detached from its
/// narrative slot or allowed to become an editing canvas.
struct TemporalPhotoHandPose: Equatable {
    static let resting = TemporalPhotoHandPose()

    var translation: CGSize = .zero
    var lift: CGFloat = 0
    var pitchDegrees: Double = 0
    var yawDegrees: Double = 0
    var rollDegrees: Double = 0

    static func held(at translation: CGSize) -> TemporalPhotoHandPose {
        let x = min(max(translation.width, -PosterSpacing.xl * 2), PosterSpacing.xl * 2)
        let y = min(max(translation.height, -PosterSpacing.xl * 1.5), PosterSpacing.xl * 1.5)
        return TemporalPhotoHandPose(
            translation: CGSize(width: x, height: y),
            lift: 0.58,
            pitchDegrees: Double(-y / (PosterSpacing.xl * 1.5)) * 4.5,
            yawDegrees: Double(x / (PosterSpacing.xl * 2)) * 6.5,
            rollDegrees: Double(x / (PosterSpacing.xl * 2)) * 1.8
        )
    }
}

/// A reusable 2.5D paper photograph. It stays a SwiftUI surface, but exposes
/// the visual signals that make it read as an object: a front, a back, a thin
/// edge, a moving protective-film highlight and a directional shadow.
struct TemporalPhotoCard: View {
    let image: UIImage?
    var foregroundMask: UIImage?
    var foregroundOffset: CGSize = .zero
    var foregroundShadowOpacity: Double = 0
    var cornerRadius: CGFloat = PosterRadius.card
    /// A caller-owned 0...1 lift value. The resting pose is always zero.
    var spatialProgress: CGFloat = 0
    var rotationXDegrees: Double = 0
    var rotationYDegrees: Double = 0
    var rotationZDegrees: Double = 0
    var paperBorderEnabled = true
    var reduceMotion = false
    var motionField: MotionFieldModel?
    var handPose: TemporalPhotoHandPose = .resting

    private var lift: CGFloat {
        reduceMotion ? 0 : FUMIRASpatialMotion.clamp(spatialProgress)
    }

    private var handLift: CGFloat { reduceMotion ? 0 : handPose.lift }
    private var renderedLift: CGFloat { max(lift, handLift) }
    private var effectivePitch: Double {
        rotationXDegrees * Double(lift) + (reduceMotion ? 0 : handPose.pitchDegrees)
    }
    private var effectiveYaw: Double {
        rotationYDegrees * Double(lift) + (reduceMotion ? 0 : handPose.yawDegrees)
    }
    private var effectiveRoll: Double {
        rotationZDegrees * Double(lift) + (reduceMotion ? 0 : handPose.rollDegrees)
    }

    private var isBackFacing: Bool {
        let wrapped = effectiveYaw.truncatingRemainder(dividingBy: 360)
        return abs(wrapped) > 90 && abs(wrapped) < 270
    }

    var body: some View {
        GeometryReader { proxy in
            card(in: proxy.size)
                .rotation3DEffect(
                    .degrees(effectivePitch),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: PosterMotion.spatialPerspective
                )
                .rotation3DEffect(
                    .degrees(effectiveYaw),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: PosterMotion.spatialPerspective
                )
                .rotationEffect(.degrees(effectiveRoll))
                .scaleEffect(1 + renderedLift * PosterMotion.spatialScalePeak)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间照片")
        .accessibilityValue("空间深度 \(Int((renderedLift * 100).rounded()))%")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private func card(in size: CGSize) -> some View {
        let boundedRadius = max(cornerRadius, 0)
        let minimumSide = max(min(size.width, size.height), 1)
        let rim = paperBorderEnabled ? min(PosterSpacing.sm, minimumSide * 0.035) : 0
        let edgeDepth = paperBorderEnabled
            ? min(PosterSpacing.sm, minimumSide * 0.022) * renderedLift
            : 0
        let frontWidth = max(size.width - rim * 2, 1)
        let frontHeight = max(size.height - rim * 2 - edgeDepth, 1)
        let frontRadius = max(boundedRadius - rim, 0)
        let cardShape = RoundedRectangle(cornerRadius: boundedRadius, style: .continuous)
        let frontShape = RoundedRectangle(cornerRadius: frontRadius, style: .continuous)

        ZStack {
            DynamicPhotoShadow(
                lift: renderedLift,
                pitch: effectivePitch,
                yaw: effectiveYaw,
                motionField: motionField,
                reduceMotion: reduceMotion,
                cornerRadius: boundedRadius
            )

            if paperBorderEnabled {
                backSurface(shape: cardShape, edgeDepth: edgeDepth)
                paperRim(shape: cardShape)
                sideEdges(shape: cardShape, edgeDepth: edgeDepth)
            }

            frontOrBack(shape: frontShape)
                .frame(width: frontWidth, height: frontHeight)
                .offset(y: -edgeDepth * 0.5)
        }
        .frame(width: max(size.width, 1), height: max(size.height, 1))
    }

    private func paperRim(shape: RoundedRectangle) -> some View {
        shape
            .fill(PosterPalette.paper)
            .overlay {
                shape.stroke(PosterEffects.photoPaperStroke, lineWidth: 1)
            }
    }

    private func backSurface(
        shape: RoundedRectangle,
        edgeDepth: CGFloat
    ) -> some View {
        shape
            .fill(PosterPalette.paperWhite)
            .overlay {
                VStack(spacing: PosterSpacing.xs) {
                    Capsule()
                        .fill(PosterPalette.actionBlue.opacity(0.18))
                        .frame(width: 34, height: 2)
                    Text("FUMIRA / TIME PRINT")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(PosterPalette.actionBlueDeep.opacity(0.42))
                }
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .offset(y: edgeDepth * 0.62)
            .opacity(isBackFacing ? 1 : 0.28 + renderedLift * 0.24)
    }

    private func sideEdges(
        shape: RoundedRectangle,
        edgeDepth: CGFloat
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(PosterPalette.ink.opacity(0.07 + renderedLift * 0.13))
                .frame(height: max(edgeDepth, 0.5))
                .frame(maxHeight: .infinity, alignment: .bottom)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(PosterPalette.ink.opacity(0.04 + abs(effectiveYaw) / 90 * 0.10))
                    .frame(width: max(edgeDepth * 0.7, 0.5))
                Spacer(minLength: 0)
                Rectangle()
                    .fill(PosterPalette.paperWhite.opacity(0.22))
                    .frame(width: max(edgeDepth * 0.7, 0.5))
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func frontOrBack(shape: RoundedRectangle) -> some View {
        ZStack {
            if !isBackFacing {
                frontContent
                    .clipShape(shape)
                    .overlay {
                        SpecularPhotoHighlight(
                            lift: renderedLift,
                            pitch: effectivePitch,
                            yaw: effectiveYaw,
                            motionField: motionField,
                            reduceMotion: reduceMotion
                        )
                        .clipShape(shape)
                    }
            } else {
                PosterPalette.paperWhite
                    .overlay {
                        VStack(spacing: PosterSpacing.xs) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .font(.title3.weight(.bold))
                            Text("FUMIRA")
                                .font(.caption.weight(.black))
                        }
                        .foregroundStyle(PosterPalette.actionBlueDeep.opacity(0.46))
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    }
                    .clipShape(shape)
            }
        }
    }

    @ViewBuilder
    private var frontContent: some View {
        if let image {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()

                if let foregroundMask {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .mask {
                            Image(uiImage: foregroundMask)
                                .resizable()
                                .scaledToFill()
                                .luminanceToAlpha()
                        }
                        .offset(foregroundOffset)
                        .shadow(
                            color: PosterPalette.ink.opacity(foregroundShadowOpacity),
                            radius: PosterSpacing.sm,
                            x: -foregroundOffset.width * 0.35,
                            y: PosterSpacing.xs
                        )
                        .accessibilityHidden(true)
                }
            }
            .compositingGroup()
        } else {
            ZStack {
                PosterPalette.skySoft
                Image(systemName: "photo")
                    .font(.system(size: PosterSpacing.xl, weight: .semibold))
                    .foregroundStyle(PosterPalette.paperWhite.opacity(0.82))
            }
        }
    }
}

private struct SpecularPhotoHighlight: View {
    let lift: CGFloat
    let pitch: Double
    let yaw: Double
    let motionField: MotionFieldModel?
    let reduceMotion: Bool

    var body: some View {
        let roll = reduceMotion ? 0 : (motionField?.roll ?? 0)
        let fieldPitch = reduceMotion ? 0 : (motionField?.pitch ?? 0)
        let x = 0.34 + CGFloat(yaw / 36 + roll * 0.16)
        let y = 0.20 + CGFloat(-pitch / 30 - fieldPitch * 0.12)
        LinearGradient(
            colors: [
                PosterPalette.paperWhite.opacity(0),
                PosterPalette.paperWhite.opacity(0.035 + lift * 0.13),
                PosterPalette.paperWhite.opacity(0),
            ],
            startPoint: UnitPoint(x: min(max(x - 0.28, 0), 1), y: min(max(y - 0.20, 0), 1)),
            endPoint: UnitPoint(x: min(max(x + 0.38, 0), 1), y: min(max(y + 0.32, 0), 1))
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DynamicPhotoShadow: View {
    let lift: CGFloat
    let pitch: Double
    let yaw: Double
    let motionField: MotionFieldModel?
    let reduceMotion: Bool
    let cornerRadius: CGFloat

    var body: some View {
        let roll = reduceMotion ? 0 : (motionField?.roll ?? 0)
        let fieldPitch = reduceMotion ? 0 : (motionField?.pitch ?? 0)
        let offset = FUMIRASpatialMotion.photoShadowOffset(
            lift: lift,
            pitch: pitch,
            yaw: yaw,
            motionRoll: roll,
            motionPitch: fieldPitch
        )
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(PosterPalette.ink.opacity(0.001))
            .shadow(
                color: PosterEffects.photoPaperShadow.opacity(0.18 + lift * 0.32),
                radius: 4 + lift * PosterEffects.photoPaperLandingShadowRadius,
                x: offset.width,
                y: offset.height
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Temporal photo paper") {
    TemporalPhotoCard(
        image: nil,
        cornerRadius: PosterRadius.card,
        spatialProgress: 0.72,
        rotationXDegrees: 5,
        rotationYDegrees: -8,
        rotationZDegrees: -1.5,
        paperBorderEnabled: true
    )
    .frame(width: 280, height: 360)
    .padding(PosterSpacing.xl)
    .background(PosterPalette.canvas)
}

#Preview("Temporal photo back") {
    TemporalPhotoCard(
        image: nil,
        spatialProgress: 1,
        rotationYDegrees: 145,
        paperBorderEnabled: true
    )
    .frame(width: 280, height: 220)
    .padding(PosterSpacing.xl)
    .background(PosterPalette.canvas)
}

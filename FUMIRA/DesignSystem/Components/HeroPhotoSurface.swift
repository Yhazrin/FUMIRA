import SwiftUI
import UIKit

enum HeroPhotoMetrics {
    static let understandingMaximumHeight: CGFloat = 360
    static let understandingHorizontalInset = PosterSpacing.xl + PosterSpacing.md
    // A slight downward landing preserves the paper-drop direction without
    // stranding the sealed target beneath a large empty band.
    static let understandingVerticalOffset = PosterSpacing.xl

    static func understandingFrame(
        aspectRatio: CGFloat,
        in size: CGSize
    ) -> CGRect {
        let ratio = max(aspectRatio, 0.01)
        let availableWidth = max(size.width - understandingHorizontalInset * 2, 1)
        let height = min(understandingMaximumHeight, availableWidth / ratio)
        let width = height * ratio
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2 + understandingVerticalOffset,
            width: width,
            height: height
        )
    }
}

/// Persistent photo host owned by ``RootView``. Survives phase swaps so the
/// capture never remounts, jumps, or fades with page opacity transitions.
struct HeroPhotoSurface: View {
    let model: AppModel
    /// RootView owns transition progression so this component remains a pure
    /// renderer of the persistent temporal photo object.
    var spatialProgress: CGFloat = 0
    /// The generated photo's time-specific reveal remains distinct from the
    /// brief spatial lift that accompanies it.
    var timeRevealProgress: CGFloat = 1
    /// Enabled only on stable, post-capture stages. Viewfinder, shutter
    /// handoff, and the result time-door keep their dedicated gestures.
    var handManipulationEnabled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanPosition = -0.8
    @State private var generatedLayerOpacity = 0.0
    @State private var handPose = TemporalPhotoHandPose.resting

    private var generatedImage: UIImage? {
        model.decodedGeneratedImage
            ?? model.generatedFrame?.imageData.flatMap(UIImage.init(data:))
    }

    private var showsUnderstandingOverlay: Bool {
        model.phase == .understanding
    }

    private var showsGeneratingOverlay: Bool {
        model.phase == .generating
    }

    private var showsSealedTarget: Bool {
        generatedImage != nil
            && (model.phase == .understanding || model.phase == .storyWriting)
    }

    private var usesPhotoPaper: Bool {
        switch model.phase {
        case .shuttered, .understanding, .storyWriting, .generating, .result:
            true
        default:
            false
        }
    }

    private var showsForegroundDepth: Bool {
        guard model.decodedForegroundMask != nil, !reduceMotion else { return false }
        switch model.phase {
        case .understanding, .storyWriting, .generating:
            return true
        default:
            return false
        }
    }

    private var foregroundDepthProgress: CGFloat {
        switch model.phase {
        case .understanding:
            return CGFloat(0.25 + model.understandingProgress * 0.75)
        case .storyWriting:
            return 1
        case .generating:
            return CGFloat(max(0.18, 1 - model.generationProgress * 0.82))
        default:
            return 0
        }
    }

    private var foregroundDepthOffset: CGSize {
        guard showsForegroundDepth else { return .zero }
        let progress = foregroundDepthProgress
        return CGSize(
            width: progress * (PosterSpacing.sm + CGFloat(model.captureMotion.roll) * PosterSpacing.md),
            height: -progress * (PosterSpacing.xs + CGFloat(model.captureMotion.pitch) * PosterSpacing.sm)
        )
    }

    /// The resting pose is deliberately flat. Only the capture handoff and the
    /// generated-result interpretation briefly drive this value toward depth.
    private var spatialRotation: (x: Double, y: Double, z: Double) {
        switch model.phase {
        case .shuttered, .understanding:
            (
                PosterMotion.captureSpatialPitchDegrees,
                PosterMotion.captureSpatialYawDegrees,
                PosterMotion.photoPaperUnderstandingRotation
            )
        case .result:
            (
                PosterMotion.resultSpatialPitchDegrees,
                PosterMotion.resultSpatialYawDegrees,
                PosterMotion.resultSpatialRollDegrees
            )
        default:
            (0, 0, 0)
        }
    }

    var body: some View {
        Group {
            if handManipulationEnabled {
                photoContent
                    .offset(handPose.translation)
                    .contentShape(Rectangle())
                    .gesture(handManipulationGesture)
            } else {
                photoContent.clipped()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(
            handManipulationEnabled ? "hero.hand-photo" : "hero.photo"
        )
        .accessibilityLabel(
            model.phase == .result ? "生成的时间场景" : "刚刚拍下的原始照片"
        )
        .accessibilityHint(
            handManipulationEnabled
                ? "拖动照片可以拿起并摆动；松手后回到原位"
                : ""
        )
        .onAppear {
            syncLayerOpacities(animated: false)
            startScanIfNeeded()
        }
        .onChange(of: model.decodedGeneratedImage != nil) { _, hasGenerated in
            if hasGenerated {
                crossfadeToGenerated()
            } else {
                generatedLayerOpacity = 0
            }
        }
        .onChange(of: model.generatedFrame?.id) { _, _ in
            syncLayerOpacities(animated: true)
        }
        .onChange(of: model.phase) { _, phase in
            syncLayerOpacities(animated: true)
            if phase == .understanding {
                startScanIfNeeded()
            }
        }
        .onChange(of: handManipulationEnabled) { _, isEnabled in
            guard !isEnabled else { return }
            handPose = .resting
        }
    }

    private var photoContent: some View {
        GeometryReader { proxy in
            ZStack {
                temporalPhoto(image: model.decodedCapturedImage)

                if let generatedImage {
                    temporalPhoto(image: generatedImage)
                        .mask {
                            if model.phase == .result {
                                TimeRevealMask(progress: timeRevealProgress)
                            } else {
                                Rectangle()
                            }
                        }
                        .opacity(generatedLayerOpacity)
                        .accessibilityHidden(true)

                    if model.phase == .result {
                        TimeRevealRipple(
                            progress: timeRevealProgress,
                            reduceMotion: reduceMotion
                        )
                    }
                }

                if model.capturedPhoto == nil, model.decodedCapturedImage == nil {
                    PosterPalette.ink.opacity(0.12)
                }

                if showsSealedTarget {
                    sealedTargetOverlay
                }

                if showsUnderstandingOverlay {
                    understandingOverlay
                }

                if showsGeneratingOverlay {
                    generatingOverlay
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func temporalPhoto(image: UIImage?) -> some View {
        TemporalPhotoCard(
            image: image,
            foregroundMask: showsForegroundDepth ? model.decodedForegroundMask : nil,
            foregroundOffset: foregroundDepthOffset,
            foregroundShadowOpacity: showsForegroundDepth
                ? Double(foregroundDepthProgress) * 0.24
                : 0,
            cornerRadius: usesPhotoPaper ? PosterRadius.photoPaper : 0,
            spatialProgress: spatialProgress,
            rotationXDegrees: spatialRotation.x,
            rotationYDegrees: spatialRotation.y,
            rotationZDegrees: spatialRotation.z,
            paperBorderEnabled: usesPhotoPaper,
            reduceMotion: reduceMotion,
            motionField: model.motionField,
            handPose: handManipulationEnabled ? handPose : .resting
        )
        .accessibilityHidden(true)
    }

    private var handManipulationGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !reduceMotion else { return }
                handPose = TemporalPhotoHandPose.held(at: value.translation)
            }
            .onEnded { _ in
                guard !reduceMotion else {
                    handPose = .resting
                    return
                }
                withAnimation(PosterMotion.photoHandSettle) {
                    handPose = .resting
                }
            }
    }

    private var understandingOverlay: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(PosterPalette.actionBlue)
                .frame(height: 4)
                .shadow(color: PosterPalette.actionBlue, radius: 10)
                .offset(y: proxy.size.height * scanPosition)
        }
        .opacity(reduceMotion ? 0 : 0.9)
        .allowsHitTesting(false)
    }

    private var sealedTargetOverlay: some View {
        ZStack {
            PosterPalette.canvas

            Canvas { context, size in
                let spacing: CGFloat = 22
                var x = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(
                        path,
                        with: .color(PosterPalette.actionBlue.opacity(0.08)),
                        lineWidth: 9
                    )
                    x += spacing
                }
            }

            VStack(spacing: PosterSpacing.sm) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(PosterPalette.actionBlue)
                Text("目标画面已封存")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PosterPalette.actionBlueDeep)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.photoPaper * 0.5, style: .continuous)
                .stroke(PosterPalette.actionBlue.opacity(0.28), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("目标画面已生成，完成故事后揭晓")
    }

    private var generatingOverlay: some View {
        TemporalParkScene(
            time: model.selectedTime,
            cornerRadius: 0,
            motionField: model.motionField
        )
        .opacity(0.15 + model.generationProgress * 0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func crossfadeToGenerated() {
        guard model.phase == .result || model.phase == .share else { return }
        // The time mask in ``TimeRevealMask`` owns result interpolation. Keep
        // this layer mounted so we do not combine it with a generic crossfade.
        generatedLayerOpacity = 1
    }

    private func syncLayerOpacities(animated: Bool) {
        let generatedTarget: Double = {
            switch model.phase {
            case .result, .share:
                return generatedImage == nil ? 0 : 1
            default:
                return 0
            }
        }()

        let apply = {
            generatedLayerOpacity = generatedTarget
        }
        if animated, !reduceMotion, model.phase != .result {
            withAnimation(.easeInOut(duration: PosterMotion.heroGeneratedCrossfade)) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func startScanIfNeeded() {
        guard showsUnderstandingOverlay, !reduceMotion else { return }
        scanPosition = -0.8
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: true)) {
            scanPosition = 0.8
        }
    }

}

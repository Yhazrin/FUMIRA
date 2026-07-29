import SwiftUI

/// One persistent waiting stage for understanding → story → generation.
/// The captured reality remains visible; business phases change the meaning of
/// the same object instead of replacing three full-screen pages.
struct RealityDevelopingView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var inspectionOffset: CGFloat = 0
    @State private var inspectionFrameIndex: Int?
    @State private var inspectionResetTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let photoFrame = RealityDevelopingGeometry.photoFrame(
                in: proxy.size,
                aspectRatio: photoAspectRatio
            )
            let rootBounds = proxy.frame(in: .named(HeroCoordinateSpace.name))

            ZStack {
                SpatialEchoContours(
                    frame: photoFrame,
                    separation: layerSeparation,
                    inspectionOffset: effectiveInspectionOffset,
                    salientRegions: model.temporalCapturePacket?
                        .visualContext.salientRegions ?? []
                )

                if let inspectionFrame {
                    TemporalSliceEcho(
                        image: inspectionFrame.image,
                        frame: photoFrame,
                        offset: effectiveInspectionOffset,
                        timeLabel: inspectionFrame.timeLabel,
                        reduceMotion: reduceMotion
                    )
                }

                HeroPhotoFrameReporter(
                    owner: slotOwner,
                    frame: photoFrame.offsetBy(
                        dx: rootBounds.minX,
                        dy: rootBounds.minY
                    ),
                    cornerRadius: PosterRadius.photoPaper
                )

                developmentHeader
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(.top, PosterSpacing.lg)
                    .safeAreaPadding(.top)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                if !dynamicTypeSize.isAccessibilitySize, let clue = resolvedClue {
                    RealityClueTag(text: clue)
                        .position(cluePosition(in: photoFrame, viewport: proxy.size))
                        .offset(x: effectiveInspectionOffset * 0.35)
                }

                developmentConsole
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(.bottom, PosterSpacing.xl)
                    .safeAreaPadding(.bottom)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(inspectionGesture)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reality.developing-stage")
        .accessibilityLabel("现实显影")
        .accessibilityHint("拖动照片可摆动；在照片外左右移动可回看现实切片")
        .accessibilityValue(
            "\(stageTitle)，\(Int(stageProgress * 100))%，\(evidenceAccessibilitySummary)"
        )
        .accessibilityAdjustableAction { direction in
            adjustInspectionFrame(direction)
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_TEMPORAL_SLICE"] == "1" {
                inspectionFrameIndex = max(
                    model.decodedMicroTimeSliceFrames.count / 2 - 1,
                    0
                )
            }
        }
        #endif
        .onDisappear {
            inspectionResetTask?.cancel()
        }
    }

    private var developmentHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                    stageHeading
                    targetBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: PosterSpacing.md) {
                    stageHeading
                    Spacer(minLength: PosterSpacing.sm)
                    targetBadge
                }
            }
        }
    }

    private var stageHeading: some View {
        Text(stageTitle)
            .font(PosterTypography.screenTitle)
            .foregroundStyle(PosterPalette.paperWhite)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var targetBadge: some View {
        Text(model.generationTargetTime.compactLabel)
            .font(PosterTypography.caption)
            .foregroundStyle(PosterPalette.ink)
            .lineLimit(1)
            .padding(.horizontal, PosterSpacing.sm)
            .frame(minHeight: 30)
            .background(
                PosterPalette.bellYellow,
                in: Capsule()
            )
    }

    private var developmentConsole: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(stageProgress * 100))%")
                    .font(PosterTypography.metric)
                    .foregroundStyle(PosterPalette.paperWhite)
                    .contentTransition(.numericText())

                Spacer(minLength: PosterSpacing.md)

                Label("可离开", systemImage: "sparkles")
                    .font(PosterTypography.label)
                    .foregroundStyle(PosterPalette.bellYellow)
            }

            ProgressView(value: stageProgress)
                .tint(PosterPalette.bellYellow)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            Button {
                model.cancelPipeline()
            } label: {
                Text("返回相机")
                    .font(PosterTypography.label)
                    .foregroundStyle(PosterPalette.paperWhite)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay {
                        Capsule()
                            .stroke(PosterPalette.paperWhite.opacity(0.32), lineWidth: 1)
                    }
            }
            .buttonStyle(PosterPressStyle())
            .accessibilityIdentifier("reality.cancel")
            .accessibilityHint("停止当前生成并回到取景器")
        }
        .padding(PosterSpacing.md)
        .background(PosterPalette.cardDark)
        .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                .stroke(PosterPalette.paperWhite.opacity(0.16), lineWidth: 1)
        }
    }

    private var inspectionGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                inspectionResetTask?.cancel()
                if !reduceMotion {
                    inspectionOffset = min(max(value.translation.width * 0.12, -14), 14)
                }
                selectInspectionFrame(for: value.translation.width)
            }
            .onEnded { _ in
                withAnimation(PosterMotion.interaction) {
                    inspectionOffset = 0
                }
                inspectionResetTask?.cancel()
                inspectionResetTask = Task { @MainActor in
                    try? await Task.sleep(for: PosterMotion.temporalSliceInspectionHold)
                    guard !Task.isCancelled else { return }
                    withAnimation(PosterMotion.interaction) {
                        inspectionFrameIndex = nil
                    }
                }
            }
    }

    private var effectiveInspectionOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return inspectionOffset + CGFloat(model.captureMotion.roll) * 9
    }

    private var photoAspectRatio: CGFloat {
        CGFloat(model.capturedPhoto?.displayAspectRatio ?? 3.0 / 4.0)
    }

    private var inspectionFrame: (image: UIImage, timeLabel: String)? {
        guard
            let index = inspectionFrameIndex,
            model.decodedMicroTimeSliceFrames.indices.contains(index)
        else {
            return nil
        }
        let image = model.decodedMicroTimeSliceFrames[index]
        let samples = model.temporalCapturePacket?.microTimeSlice.frames ?? []
        guard samples.indices.contains(index) else {
            return (image, "快门切片")
        }
        let offset = samples[index].offsetFromShutter
        let sign = offset > 0 ? "+" : ""
        return (image, "\(sign)\(offset.formatted(.number.precision(.fractionLength(2)))) 秒")
    }

    private func selectInspectionFrame(for translation: CGFloat) {
        let count = model.decodedMicroTimeSliceFrames.count
        guard count > 0 else {
            inspectionFrameIndex = nil
            return
        }
        let normalized = min(max((translation / 140 + 1) / 2, 0), 1)
        inspectionFrameIndex = min(
            Int((normalized * CGFloat(count)).rounded(.down)),
            count - 1
        )
    }

    private func adjustInspectionFrame(_ direction: AccessibilityAdjustmentDirection) {
        let count = model.decodedMicroTimeSliceFrames.count
        guard count > 0 else { return }
        let current = inspectionFrameIndex ?? count / 2
        switch direction {
        case .increment:
            inspectionFrameIndex = min(current + 1, count - 1)
        case .decrement:
            inspectionFrameIndex = max(current - 1, 0)
        @unknown default:
            break
        }
    }

}

enum RealityDevelopingGeometry {
    static func photoFrame(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
        let maximumWidth = max(size.width - PosterSpacing.xl * 2, 1)
        let maximumHeight = max(size.height * 0.44, 1)
        let ratio = max(aspectRatio, 0.01)
        let width = min(maximumWidth, maximumHeight * ratio)
        let height = min(maximumHeight, width / ratio)
        return CGRect(
            x: (size.width - width) / 2,
            y: max(size.height * 0.20, 136),
            width: width,
            height: height
        )
    }
}

private extension RealityDevelopingView {
    private var slotOwner: HeroSlotOwner {
        switch model.phase {
        case .understanding: .understanding
        case .storyWriting: .storyWriting
        case .generating: .generating
        default: .understanding
        }
    }

    private var stageProgress: Double {
        switch model.phase {
        case .understanding: model.understandingProgress
        case .storyWriting: model.storyProgress
        case .generating: model.generationProgress
        default: 0
        }
    }

    private var layerSeparation: CGFloat {
        switch model.phase {
        case .understanding:
            4 + CGFloat(model.understandingProgress) * 8
        case .storyWriting:
            12
        case .generating:
            12 * CGFloat(max(0, 1 - model.generationProgress))
        default:
            0
        }
    }

    private var stageTitle: String {
        switch model.phase {
        case .understanding: "拆开现实"
        case .storyWriting: "找到因果"
        case .generating: "聚合时间"
        default: "现实显影"
        }
    }

    /// Concrete scene claims appear only after the understanding provider has
    /// returned them; before that the UI stays honest and process-oriented.
    private var resolvedClue: String? {
        guard let understanding = model.sceneUnderstanding else { return nil }
        if model.temporalCapturePacket?.subjectAnchor != nil,
           let subject = understanding.subjects.first {
            return "主体 · \(subject.name)"
        }
        if let anchor = understanding.spatialAnchors?.first {
            return [anchor.name, anchor.depth].compactMap { $0 }.joined(separator: " · ")
        }
        if let subject = understanding.subjects.first {
            return subject.name
        }
        return understanding.timeClues.first
    }

    private func cluePosition(in frame: CGRect, viewport: CGSize) -> CGPoint {
        let horizontalLimit = PosterSpacing.xl * 3
        guard let anchor = model.temporalCapturePacket?.subjectAnchor else {
            return CGPoint(
                x: min(
                    frame.maxX - PosterSpacing.xl,
                    viewport.width - horizontalLimit
                ),
                y: frame.minY + frame.height * 0.28
            )
        }
        let proposed = CGPoint(
            x: frame.minX + CGFloat(anchor.normalizedX) * frame.width,
            y: frame.minY + CGFloat(anchor.normalizedY) * frame.height
                - PosterSpacing.xl * 2
        )
        return CGPoint(
            x: min(
                max(proposed.x, horizontalLimit),
                max(
                    viewport.width - horizontalLimit,
                    horizontalLimit
                )
            ),
            y: min(
                max(proposed.y, frame.minY + PosterSpacing.xl),
                max(
                    frame.maxY - PosterSpacing.xl,
                    frame.minY + PosterSpacing.xl
                )
            )
        )
    }

    private var compactEvidenceText: String {
        let frameCount = model.temporalCapturePacket?.microTimeSlice.frames.count ?? 0
        return frameCount > 0 ? "\(frameCount) 帧切片" : "主照片"
    }

    private var visualLayerCount: Int {
        let context = model.temporalCapturePacket?.visualContext
        if context?.foregroundMaskPNG != nil {
            return max(context?.salientRegions.count ?? 0, 1) + 1
        }
        return context?.salientRegions.count ?? 0
    }

    private var evidenceAccessibilitySummary: String {
        var values = [compactEvidenceText]
        values.append(
            model.temporalCapturePacket?.motion.wasAnchored == true
                ? "已定锚"
                : "姿态已记录"
        )
        if visualLayerCount > 0 {
            values.append("\(visualLayerCount) 层场景")
        }
        if let optical = model.temporalCapturePacket?.opticalContext,
           optical.isAvailable {
            values.append(optical.lightCondition.shortLabel)
        }
        return values.joined(separator: "，")
    }
}

private struct TemporalSliceEcho: View {
    let image: UIImage
    let frame: CGRect
    let offset: CGFloat
    let timeLabel: String
    let reduceMotion: Bool

    var body: some View {
        let slitWidth = max(frame.width * 0.28, 1)
        let slitOffset = reduceMotion ? 0 : offset * 4
        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: frame.width, height: frame.height)
                .saturation(0.72)
                .contrast(1.12)
                .opacity(reduceMotion ? 0.78 : 0.66)
                .mask {
                    Rectangle()
                        .frame(width: slitWidth)
                        .offset(x: slitOffset)
                }

            Rectangle()
                .fill(PosterPalette.bellYellow.opacity(0.72))
                .frame(width: 1)
                .offset(x: (frame.width - slitWidth) / 2 + slitOffset)

            Rectangle()
                .fill(PosterPalette.bellYellow.opacity(0.72))
                .frame(width: 1)
                .offset(x: (frame.width + slitWidth) / 2 + slitOffset)

            Text(timeLabel)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(PosterPalette.ink)
                .padding(.horizontal, PosterSpacing.sm)
                .frame(minHeight: 26)
                .background(PosterPalette.bellYellow, in: Capsule())
                .padding(PosterSpacing.sm)
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: PosterRadius.photoPaper,
                style: .continuous
            )
        )
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("reality.temporal-slice")
        .accessibilityLabel("快门现实切片 \(timeLabel)")
    }
}

private struct SpatialEchoContours: View {
    let frame: CGRect
    let separation: CGFloat
    let inspectionOffset: CGFloat
    let salientRegions: [TemporalSalientRegion]

    var body: some View {
        ZStack {
            contour(depth: -1, opacity: 0.20)
            contour(depth: 0, opacity: 0.34)
            contour(depth: 1, opacity: 0.18)

            ForEach(salientRegions.prefix(3)) { region in
                salientContour(region: region)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func contour(depth: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: PosterRadius.photoPaper, style: .continuous)
            .stroke(
                depth == 0 ? PosterPalette.bellYellow : PosterPalette.paperWhite,
                style: StrokeStyle(lineWidth: depth == 0 ? 1.5 : 1, dash: depth == 0 ? [] : [3, 5])
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .offset(
                x: depth * (separation + inspectionOffset),
                y: depth * separation * 0.42
            )
            .opacity(opacity)
    }

    private func salientContour(region: TemporalSalientRegion) -> some View {
        let regionFrame = CGRect(
            x: frame.minX + CGFloat(region.normalizedX) * frame.width,
            y: frame.minY + CGFloat(region.normalizedY) * frame.height,
            width: CGFloat(region.normalizedWidth) * frame.width,
            height: CGFloat(region.normalizedHeight) * frame.height
        )
        return RoundedRectangle(cornerRadius: PosterRadius.control, style: .continuous)
            .stroke(
                PosterPalette.bellYellow.opacity(0.78),
                style: StrokeStyle(lineWidth: 1, dash: [2, 4])
            )
            .frame(
                width: max(regionFrame.width, PosterSpacing.xl),
                height: max(regionFrame.height, PosterSpacing.xl)
            )
            .position(x: regionFrame.midX, y: regionFrame.midY)
            .offset(
                x: separation * 0.52 + inspectionOffset * 0.7,
                y: -separation * 0.20
            )
            .shadow(
                color: PosterPalette.bellYellow.opacity(0.18),
                radius: PosterSpacing.xs
            )
    }
}

private struct RealityClueTag: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(PosterPalette.bellYellow)
                .frame(width: 6, height: 6)
            Text(text)
                .font(PosterTypography.caption)
                .lineLimit(2)
        }
        .foregroundStyle(PosterPalette.paperWhite)
        .padding(.horizontal, PosterSpacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: 150, alignment: .leading)
        .background(PosterPalette.cardDark)
        .clipShape(RoundedRectangle(cornerRadius: PosterRadius.control, style: .continuous))
    }
}

struct FrozenRealityBackdrop: View {
    let image: UIImage?
    let motion: CaptureMotionModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PosterPalette.ink

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.08)
                        .blur(radius: 10)
                        .offset(
                            x: reduceMotion ? 0 : CGFloat(motion.roll) * -8,
                            y: reduceMotion ? 0 : CGFloat(motion.pitch) * 6
                        )
                        .opacity(0.52)
                        .clipped()
                }

                PosterPalette.ink.opacity(0.42)

                LinearGradient(
                    colors: [
                        PosterPalette.ink.opacity(0.52),
                        Color.clear,
                        PosterPalette.ink.opacity(0.68),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

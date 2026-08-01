import SwiftUI

/// One persistent waiting stage for understanding → story → generation.
/// The captured reality remains visible; business phases change the meaning of
/// the same object instead of replacing three full-screen pages.
struct RealityDevelopingView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                ZStack {
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
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .simultaneousGesture(inspectionGesture)

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reality.developing-stage")
        .accessibilityLabel("时间生成")
        .accessibilityHint("左右转动照片可回答时间问题；在照片外左右移动可回看时间切片")
        .accessibilityValue(
            "\(silentStageSummary)，\(evidenceAccessibilitySummary)"
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
        HStack {
            cancelPipelineButton
            Spacer(minLength: PosterSpacing.md)
            targetBadge
        }
    }

    private var targetBadge: some View {
        Label(model.generationTargetTime.compactLabel, systemImage: "clock")
            .font(PosterTypography.caption)
            .foregroundStyle(PosterPalette.mutedInk)
            .lineLimit(1)
            .accessibilityLabel("目标时间 (model.generationTargetTime.compactLabel)")
    }

    @ViewBuilder
    private var cancelPipelineButton: some View {
        if #available(iOS 26.0, *) {
            cancelPipelineControl
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(minWidth: 44, minHeight: 44)
        } else {
            cancelPipelineControl
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(PosterPalette.ink)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    private var cancelPipelineControl: some View {
        Button {
            model.cancelPipeline()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
        }
        .accessibilityIdentifier("reality.cancel")
        .accessibilityLabel("返回相机")
        .accessibilityHint("停止当前生成并回到取景器")
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
        let maximumHeight = max(size.height * 0.60, 1)
        let ratio = max(aspectRatio, 0.01)
        let width = min(maximumWidth, maximumHeight * ratio)
        let height = min(maximumHeight, width / ratio)
        return CGRect(
            x: (size.width - width) / 2,
            y: max((size.height - height) * 0.5, 128),
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

    private var silentStageSummary: String {
        switch model.phase {
        case .understanding: "正在读取这张照片"
        case .storyWriting: "正在编织时间线索"
        case .generating: "正在抵达目标时间"
        default: "正在处理"
        }
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
                .fill(PosterPalette.paperWhite.opacity(0.78))
                .frame(width: 1)
                .offset(x: (frame.width - slitWidth) / 2 + slitOffset)

            Rectangle()
                .fill(PosterPalette.paperWhite.opacity(0.78))
                .frame(width: 1)
                .offset(x: (frame.width + slitWidth) / 2 + slitOffset)

            Text(timeLabel)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .padding(.horizontal, PosterSpacing.sm)
                .frame(minHeight: 26)
                .background(PosterPalette.paperWhite, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(PosterPalette.actionBlue.opacity(0.35), lineWidth: 1)
                }
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
        .accessibilityLabel("时间切片 \(timeLabel)")
    }
}

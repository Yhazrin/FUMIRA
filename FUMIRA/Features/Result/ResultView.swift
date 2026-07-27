import SwiftUI
import UIKit

struct ResultView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panelDetent: ResultPanelDetent = .controls
    @GestureState private var panelDrag = CGFloat.zero

    private var generatedTime: TimePosition {
        model.generatedFrame?.time ?? model.generationTargetTime
    }

    private var generatedImage: UIImage? {
        model.decodedGeneratedImage
            ?? model.generatedFrame?.imageData.flatMap(UIImage.init(data:))
    }

    /// The generated result owns its own geometry. Never force it back into the
    /// camera-source ratio because relay providers may return a corrected size.
    private var photoAspectRatio: CGFloat {
        if let generatedImage, generatedImage.size.height > 0 {
            return generatedImage.size.width / generatedImage.size.height
        }
        if let ratio = model.generatedPhoto?.displayAspectRatio, ratio > 0 {
            return CGFloat(ratio)
        }
        if let ratio = model.capturedPhoto?.displayAspectRatio, ratio > 0 {
            return CGFloat(ratio)
        }
        return 3.0 / 4.0
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = ResultLayoutGeometry.layout(
                in: proxy.size,
                safeAreaTop: proxy.safeAreaInsets.top,
                safeAreaBottom: proxy.safeAreaInsets.bottom,
                aspectRatio: photoAspectRatio
            )
            let panelOffset = currentPanelOffset(maximum: layout.maximumPanelPull)
            let revealProgress = layout.maximumPanelPull > 0
                ? panelOffset / layout.maximumPanelPull
                : 0

            ZStack(alignment: .top) {
                PosterPalette.canvas

                resultHeader(width: layout.viewportWidth, revealProgress: revealProgress)
                    .zIndex(1)

                heroPhoto(revealProgress: revealProgress)
                    .frame(width: layout.photoSize.width, height: layout.photoSize.height)
                    .position(
                        x: layout.viewportWidth / 2,
                        y: layout.photoTop + layout.photoSize.height / 2
                    )
                    .zIndex(0)

                bottomChrome(
                    width: layout.viewportWidth,
                    height: layout.panelHeight,
                    safeAreaBottom: layout.safeAreaBottom,
                    maximumPull: layout.maximumPanelPull
                )
                .offset(y: layout.panelTop + panelOffset)
                .zIndex(2)
            }
            .frame(width: layout.viewportWidth, height: proxy.size.height)
            .clipped()
        }
        .background(PosterPalette.canvas)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_RESULT_PANEL"] == "photo" {
                panelDetent = .photo
            }
            #endif
        }
    }

    private func resultHeader(width: CGFloat, revealProgress: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("时间的回信")
                .font(PosterTypography.display(27))
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("目标 \(generatedTime.compactLabel)")
                .font(.caption.weight(.bold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .contentTransition(.numericText())
        }
        .frame(
            width: max(width - PosterSpacing.md * 2 - 60, 1),
            alignment: .leading
        )
        .padding(.horizontal, PosterSpacing.md)
        .padding(.top, PosterSpacing.xs)
        .frame(width: width, alignment: .leading)
        .offset(y: -4 * revealProgress)
        .opacity(1 - 0.28 * revealProgress)
    }

    private func heroPhoto(revealProgress: CGFloat) -> some View {
        let cornerRadius = PosterRadius.card * (1 - 0.5 * revealProgress)

        return ZStack(alignment: .topTrailing) {
            PosterPalette.ink.opacity(0.06)

            if let generatedImage {
                Image(uiImage: generatedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("生成的目标时间照片")
            } else {
                VStack(spacing: PosterSpacing.sm) {
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .medium))
                    Text("目标照片")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(PosterPalette.mutedInk)
            }

            Text(generatedTime.compactLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(PosterPalette.paperWhite)
                .padding(.horizontal, PosterSpacing.sm)
                .padding(.vertical, PosterSpacing.xs)
                .background(PosterPalette.actionBlueDeep.opacity(0.88))
                .clipShape(Capsule())
                .padding(PosterSpacing.md)
                .accessibilityLabel("目标年份 \(generatedTime.compactLabel)")
                .opacity(1 - 0.2 * revealProgress)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(PosterPalette.line.opacity(0.72), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: PosterPalette.ink.opacity(0.1), radius: 10, y: 5)
    }

    private func bottomChrome(
        width: CGFloat,
        height: CGFloat,
        safeAreaBottom: CGFloat,
        maximumPull: CGFloat
    ) -> some View {
        let contentWidth = ResultLayoutGeometry.contentWidth(in: width)

        return VStack(spacing: 0) {
            panelHandle(maximumPull: maximumPull)

            ScrollView(.vertical) {
                VStack(spacing: PosterSpacing.md) {
                    narrativeSection
                        .frame(width: contentWidth)

                    Divider()
                        .frame(width: contentWidth)

                    TimeRail(
                        value: model.selectedTime.normalized,
                        onDetent: model.playTimeDetent
                    ) { normalized in
                        model.updateTime(normalized: normalized)
                    }
                    .frame(width: contentWidth)

                    primaryActions(width: contentWidth)
                    secondaryActions(width: contentWidth)
                }
                .padding(.bottom, max(safeAreaBottom, PosterSpacing.lg))
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: width, height: height, alignment: .top)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: PosterRadius.card,
                topTrailingRadius: PosterRadius.card
            )
            .fill(PosterPalette.canvas)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: PosterRadius.card,
                    topTrailingRadius: PosterRadius.card
                )
                .stroke(PosterPalette.line.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: PosterPalette.ink.opacity(0.09), radius: 12, y: -3)
            .ignoresSafeArea(edges: .bottom)
        }
        .background(alignment: .bottom) {
            PosterPalette.canvas
                .frame(width: width, height: maximumPull + safeAreaBottom + 4)
                .offset(y: maximumPull)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func panelHandle(maximumPull: CGFloat) -> some View {
        VStack(spacing: PosterSpacing.xs) {
            Capsule()
                .fill(PosterPalette.actionBlue.opacity(0.35))
                .frame(width: 42, height: 5)

            Image(systemName: panelDetent == .controls ? "chevron.down" : "chevron.up")
                .font(.caption2.weight(.bold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .gesture(panelDragGesture(maximumPull: maximumPull))
        .onTapGesture {
            setPanelDetent(panelDetent == .controls ? .photo : .controls)
        }
        .accessibilityElement()
        .accessibilityLabel(panelDetent == .controls ? "展开照片" : "恢复操作面板")
        .accessibilityHint("上下拖动或轻点切换照片与操作区域")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            setPanelDetent(panelDetent == .controls ? .photo : .controls)
        }
    }

    @ViewBuilder
    private func primaryActions(width: CGFloat) -> some View {
        let layout = ResultLayoutGeometry.primaryActionLayout(in: width)
        if !layout.isStacked {
            HStack(spacing: layout.spacing) {
                saveButton
                    .frame(width: layout.buttonWidth)
                regenerateButton
                    .frame(width: layout.buttonWidth)
            }
            .frame(width: width)
        } else {
            VStack(spacing: PosterSpacing.sm) {
                saveButton
                regenerateButton
            }
            .frame(width: width)
        }
    }

    private var saveButton: some View {
        PosterCapsuleButton(
            title: "保存海报",
            accessibilityHint: "打开海报预览，可保存到相册或系统分享"
        ) {
            model.openShare()
        }
    }

    private var regenerateButton: some View {
        PosterCapsuleButton(
            title: "重新生成",
            style: .accent,
            accessibilityHint: "用原图重新生成拍摄时锁定的目标年份"
        ) {
            Task { await model.regenerateResult() }
        }
    }

    private func secondaryActions(width: CGFloat) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: PosterSpacing.sm),
                GridItem(.flexible(), spacing: PosterSpacing.sm),
            ],
            spacing: PosterSpacing.sm
        ) {
            ResultTextAction(
                title: "生成浏览年份",
                systemImage: "clock.arrow.circlepath"
            ) {
                Task { await model.generateAtStoryPreviewTime() }
            }

            ResultTextAction(title: "重拍", systemImage: "camera.rotate") {
                model.retake()
            }

            if model.canUndoGeneration {
                ResultTextAction(title: "撤销", systemImage: "arrow.uturn.backward") {
                    model.undoLastGeneration()
                }
            }
        }
        .frame(width: width)
    }

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            Text(model.temporalStory?.title ?? "这一刻的时间故事")
                .font(.headline)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(2)

            Text("故事浏览 · \(model.selectedTime.compactLabel)")
                .font(.caption.weight(.bold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .contentTransition(.numericText())

            Text(model.currentNarrative)
                .font(.footnote)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func currentPanelOffset(maximum: CGFloat) -> CGFloat {
        let restingOffset = panelDetent == .photo ? maximum : 0
        return min(max(restingOffset + panelDrag, 0), maximum)
    }

    private func panelDragGesture(maximumPull: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($panelDrag) { value, state, _ in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }
                state = value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }
                let restingOffset = panelDetent == .photo ? maximumPull : 0
                let predictedOffset = min(
                    max(restingOffset + value.predictedEndTranslation.height, 0),
                    maximumPull
                )
                setPanelDetent(predictedOffset >= maximumPull * 0.42 ? .photo : .controls)
            }
    }

    private func setPanelDetent(_ detent: ResultPanelDetent) {
        withAnimation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : .spring(response: 0.34, dampingFraction: 0.84)
        ) {
            panelDetent = detent
        }
    }
}

enum ResultLayoutGeometry {
    private static let headerHeight: CGFloat = 58
    private static let preferredPanelHeight: CGFloat = 390
    private static let minimumVisiblePanelHeight: CGFloat = 116

    struct Layout: Equatable {
        var viewportWidth: CGFloat
        var photoSize: CGSize
        var photoTop: CGFloat
        var panelTop: CGFloat
        var panelHeight: CGFloat
        var safeAreaBottom: CGFloat
        var maximumPanelPull: CGFloat
    }

    struct PrimaryActionLayout: Equatable {
        var isStacked: Bool
        var buttonWidth: CGFloat
        var spacing: CGFloat
    }

    static func layout(
        in container: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        aspectRatio: CGFloat
    ) -> Layout {
        let viewportWidth = max(container.width, 1)
        // RootView keeps result content inside the system safe area already.
        // GeometryReader still reports the window inset here, so adding it a
        // second time leaves an oversized gap between the header and photo.
        let photoTop = headerHeight
        let photoSize = photoSize(
            in: container,
            safeAreaTop: photoTop,
            aspectRatio: aspectRatio
        )
        let preferredTop = container.height - preferredPanelHeight
        let photoDrivenTop = photoTop + photoSize.height * 0.62
        let maximumTop = max(container.height - minimumVisiblePanelHeight, 0)
        let panelTop = min(
            max(max(preferredTop, photoDrivenTop), headerHeight + 120),
            maximumTop
        )
        let panelHeight = max(container.height - panelTop, minimumVisiblePanelHeight)
        let photoBottom = photoTop + photoSize.height
        let desiredReveal = max(photoBottom - panelTop + PosterSpacing.md, 96)
        let maximumPanelPull = min(
            desiredReveal,
            max(panelHeight - minimumVisiblePanelHeight, 0)
        )

        return Layout(
            viewportWidth: viewportWidth,
            photoSize: photoSize,
            photoTop: photoTop,
            panelTop: panelTop,
            panelHeight: panelHeight,
            safeAreaBottom: max(safeAreaBottom, 0),
            maximumPanelPull: maximumPanelPull
        )
    }

    static func layout(
        in container: CGSize,
        safeAreaTop: CGFloat,
        aspectRatio: CGFloat
    ) -> Layout {
        layout(
            in: container,
            safeAreaTop: safeAreaTop,
            safeAreaBottom: 0,
            aspectRatio: aspectRatio
        )
    }

    static func photoSize(
        in container: CGSize,
        safeAreaTop: CGFloat,
        aspectRatio: CGFloat
    ) -> CGSize {
        let ratio = max(aspectRatio, 0.01)
        let availableWidth = max(container.width, 1)
        let maximumHeight = max(container.height - safeAreaTop - PosterSpacing.sm, 1)
        let widthDrivenHeight = availableWidth / ratio

        if widthDrivenHeight <= maximumHeight {
            return CGSize(width: availableWidth, height: widthDrivenHeight)
        }
        return CGSize(width: maximumHeight * ratio, height: maximumHeight)
    }

    static func contentWidth(in viewportWidth: CGFloat) -> CGFloat {
        max(viewportWidth - PosterSpacing.md * 2, 1)
    }

    static func primaryActionLayout(in contentWidth: CGFloat) -> PrimaryActionLayout {
        let width = max(contentWidth, 1)
        let spacing = PosterSpacing.sm
        if width < 330 {
            return PrimaryActionLayout(
                isStacked: true,
                buttonWidth: width,
                spacing: spacing
            )
        }
        return PrimaryActionLayout(
            isStacked: false,
            buttonWidth: max((width - spacing) / 2, 1),
            spacing: spacing
        )
    }
}

private enum ResultPanelDetent: Equatable {
    case controls
    case photo
}

private struct ResultTextAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .frame(maxWidth: .infinity, minHeight: 44)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, PosterSpacing.xs)
                .background(PosterPalette.actionBlue.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: PosterRadius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel(title)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            ResultView(model: PreviewFixtures.model(phase: .result), namespace: namespace)
        }
    }
    return PreviewWrapper()
}

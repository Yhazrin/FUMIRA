import SwiftUI
import UIKit

struct ResultView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// One continuous source of truth for the sheet. The old split between a
    /// detent and `@GestureState` could briefly resolve to two offsets when a
    /// drag ended, which made the sheet flash rather than follow the finger.
    @State private var panelProgress: CGFloat = 0
    @State private var panelDragOrigin: CGFloat?
    @State private var revealBaselineYaw: Double?

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleResult
            } else {
                immersiveResult
            }
        }
        .background(Color.clear)
        .onAppear {
            revealBaselineYaw = model.captureMotion.yaw
            #if DEBUG
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_RESULT_PANEL"] == "photo" {
                panelProgress = 1
            }
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_RESULT_REVEAL"] == "1" {
                model.completeResultReveal()
            }
            if let rawProgress = ProcessInfo.processInfo.environment[
                "FUMIRA_AUDIT_RESULT_REVEAL_PROGRESS"
            ],
               let progress = Double(rawProgress) {
                model.updateResultRevealProgress(CGFloat(progress))
            }
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_REALITY_ALIGNMENT"] == "1" {
                model.completeResultReveal()
                model.isRealityAlignmentPresented = true
            }
            #endif
        }
        .onChange(of: model.captureMotion.yaw) { _, yaw in
            updateRevealFromDeviceYaw(yaw)
        }
    }

    private var immersiveResult: some View {
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
            let photoFrame = CGRect(
                x: (layout.viewportWidth - layout.photoSize.width) / 2,
                y: layout.photoTop,
                width: layout.photoSize.width,
                height: layout.photoSize.height
            )

            ZStack(alignment: .top) {
                // The generated photo remains mounted in RootView from the
                // capture pipeline. This page publishes its destination frame
                // rather than rebuilding a second image card above it.
                Color.clear

                resultHeader(width: layout.viewportWidth, revealProgress: revealProgress)
                    .zIndex(1)

                HeroPhotoSlot(
                    owner: .result,
                    aspectRatio: photoAspectRatio,
                    cornerRadius: PosterRadius.card,
                    fixedFrame: photoFrame
                )
                    .zIndex(0)

                if model.resultRevealProgress < 0.999 {
                    TimeDoorPrompt(
                        target: generatedTime,
                        progress: model.resultRevealProgress
                    ) {
                        withAnimation(
                            reduceMotion
                                ? .linear(duration: PosterMotion.reduced)
                                : PosterMotion.timeReveal
                        ) {
                            model.completeResultReveal()
                        }
                    }
                    .frame(width: photoFrame.width, height: photoFrame.height)
                    .position(x: photoFrame.midX, y: photoFrame.midY)
                    // The draggable result sheet is inserted later in this
                    // ZStack. Keep the time door above it for both rendering
                    // and hit testing; equal z-indices let the sheet's clear
                    // region steal the fallback button tap.
                    .zIndex(3)
                }

                if model.isRealityAlignmentPresented {
                    RealityAlignmentOverlay(
                        model: model,
                        generated: generatedImage,
                        target: generatedTime
                    ) {
                        withAnimation(PosterMotion.interaction) {
                            model.isRealityAlignmentPresented = false
                        }
                    }
                    .frame(
                        width: layout.viewportWidth,
                        height: proxy.size.height
                    )
                    .zIndex(4)
                }

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
    }

    private var accessibleResult: some View {
        ZStack {
            PosterScreenContainer(background: .clear) {
                VStack(alignment: .leading, spacing: PosterSpacing.lg) {
                    Text("时间的回信")
                        .font(PosterTypography.screenTitle)
                        .foregroundStyle(PosterPalette.ink)
                        .accessibilityAddTraits(.isHeader)

                    ZStack {
                        HeroPhotoSlot(
                            owner: .result,
                            aspectRatio: photoAspectRatio,
                            maximumHeight: ResultLayoutGeometry.accessiblePhotoMaximumHeight,
                            cornerRadius: PosterRadius.card
                        )

                        if model.resultRevealProgress < 0.999 {
                            TimeDoorPrompt(
                                target: generatedTime,
                                progress: model.resultRevealProgress
                            ) {
                                withAnimation(
                                    reduceMotion
                                        ? .linear(duration: PosterMotion.reduced)
                                        : PosterMotion.timeReveal
                                ) {
                                    model.completeResultReveal()
                                }
                            }
                        }
                    }

                    narrativeSection

                    TimeRail(
                        value: model.selectedTime.normalized,
                        onDetent: model.playTimeDetent
                    ) { normalized in
                        model.updateTime(normalized: normalized)
                    }

                    accessibleActions
                }
            }

            if model.isRealityAlignmentPresented {
                RealityAlignmentOverlay(
                    model: model,
                    generated: generatedImage,
                    target: generatedTime
                ) {
                    withAnimation(PosterMotion.interaction) {
                        model.isRealityAlignmentPresented = false
                    }
                }
                .zIndex(4)
            }
        }
    }

    private var accessibleActions: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            saveButton

            if model.resultRevealProgress >= 0.999 {
                quietAction(
                    title: "对准现实",
                    systemImage: "viewfinder"
                ) {
                    withAnimation(PosterMotion.interaction) {
                        model.isRealityAlignmentPresented = true
                    }
                }
            }

            moreActionsMenu
        }
        .frame(maxWidth: .infinity)
    }

    private func resultHeader(width: CGFloat, revealProgress: CGFloat) -> some View {
        VStack(alignment: .leading) {
            Text("时间的回信")
                .font(PosterTypography.sectionTitle)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

    private func bottomChrome(
        width: CGFloat,
        height: CGFloat,
        safeAreaBottom: CGFloat,
        maximumPull: CGFloat
    ) -> some View {
        let contentWidth = ResultLayoutGeometry.contentWidth(in: width)

        return VStack(spacing: 0) {
            panelHandle(maximumPull: maximumPull)

            // Keep the decision to keep the poster immediately reachable.
            // Narrative and time browsing can scroll below it; the principal
            // action must not be buried beneath a second gesture surface.
            resultActionShelf(width: contentWidth)
                .padding(.horizontal, PosterSpacing.md)
                .padding(.bottom, PosterSpacing.sm)

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
            .stroke(PosterEffects.cardStroke, lineWidth: 1)
            }
            .shadow(color: PosterEffects.cardShadow, radius: 10, y: -2)
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

            Image(systemName: panelProgress < 0.5 ? "chevron.down" : "chevron.up")
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.actionBlueDeep)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(Rectangle())
        .gesture(panelDragGesture(maximumPull: maximumPull))
        .onTapGesture {
            setPanelProgress(panelProgress < 0.5 ? 1 : 0)
        }
        .accessibilityElement()
        .accessibilityIdentifier("result.panel-handle")
        .accessibilityLabel(panelProgress < 0.5 ? "展开照片" : "恢复操作面板")
        .accessibilityValue(panelProgress < 0.5 ? "操作" : "照片")
        .accessibilityHint("上下拖动或轻点切换照片与操作区域")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            setPanelProgress(panelProgress < 0.5 ? 1 : 0)
        }
    }

    private func resultActionShelf(width: CGFloat) -> some View {
        VStack(spacing: PosterSpacing.sm) {
            // Leaving with the poster is the one primary result action. Every
            // other operation is contextual or destructive, so it should not
            // visually compete with saving.
            saveButton

            HStack(spacing: PosterSpacing.md) {
                if model.resultRevealProgress >= 0.999 {
                    quietAction(
                        title: "对准现实",
                        systemImage: "viewfinder"
                    ) {
                        withAnimation(PosterMotion.interaction) {
                            model.isRealityAlignmentPresented = true
                        }
                    }
                }

                moreActionsMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
    }

    private var saveButton: some View {
        PosterCapsuleButton(
            title: "保存海报",
            accessibilityHint: "打开海报预览，可保存到相册或系统分享"
        ) {
            model.openShare()
        }
        .posterSensoryFeedback(
            trigger: model.shareFeedbackMessage == "已保存到相册",
            .success
        )
    }

    private func quietAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(PosterTypography.label)
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel(title)
    }

    private var moreActionsMenu: some View {
        Menu {
            Button {
                Task { await model.generateAtStoryPreviewTime() }
            } label: {
                Label("生成这一帧", systemImage: "clock.arrow.circlepath")
            }

            Button {
                Task { await model.regenerateResult() }
            } label: {
                Label("重新生成", systemImage: "sparkles")
            }

            if model.canUndoGeneration {
                Button {
                    model.undoLastGeneration()
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()

            Button(role: .destructive) {
                model.retake()
            } label: {
                Label("重拍", systemImage: "camera.rotate")
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
                .font(PosterTypography.label)
                .foregroundStyle(PosterPalette.ink.opacity(0.66))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityIdentifier("result.more-actions")
        .accessibilityHint("生成、重新生成和重拍")
    }

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            Text(model.temporalStory?.title ?? "这一刻的时间故事")
                .font(PosterTypography.cardTitle)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(2)

            Text(model.currentNarrative)
                .font(PosterTypography.body)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func currentPanelOffset(maximum: CGFloat) -> CGFloat {
        min(max(panelProgress, 0), 1) * maximum
    }

    private func panelDragGesture(maximumPull: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }
                if panelDragOrigin == nil {
                    panelDragOrigin = panelProgress
                }
                let origin = panelDragOrigin ?? panelProgress
                let progressDelta = value.translation.height / max(maximumPull, 1)
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    panelProgress = min(max(origin + progressDelta, 0), 1)
                }
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    panelDragOrigin = nil
                    return
                }
                let origin = panelDragOrigin ?? panelProgress
                panelDragOrigin = nil
                let predictedProgress = origin
                    + value.predictedEndTranslation.height / max(maximumPull, 1)
                setPanelProgress(predictedProgress >= 0.42 ? 1 : 0)
            }
    }

    private func setPanelProgress(_ progress: CGFloat) {
        withAnimation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : PosterMotion.resultPanelSettle
        ) {
            panelProgress = min(max(progress, 0), 1)
        }
    }

    private func updateRevealFromDeviceYaw(_ yaw: Double) {
        guard !reduceMotion, model.resultRevealProgress < 1 else { return }
        guard let baseline = revealBaselineYaw else {
            revealBaselineYaw = yaw
            return
        }
        model.updateResultRevealProgress(
            Self.revealProgress(yaw: yaw, baseline: baseline)
        )
    }

    static func revealProgress(yaw: Double, baseline: Double) -> CGFloat {
        let delta = normalizedAngle(yaw - baseline)
        return CGFloat(min(abs(delta) / 0.23, 1))
    }

    static func normalizedAngle(_ value: Double) -> Double {
        var angle = value
        while angle > .pi { angle -= .pi * 2 }
        while angle < -.pi { angle += .pi * 2 }
        return angle
    }
}

private struct TimeDoorPrompt: View {
    let target: TimePosition
    let progress: CGFloat
    let complete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clampedProgress = FUMIRASpatialMotion.clamp(progress)
        let departure = reduceMotion
            ? CGFloat.zero
            : FUMIRASpatialMotion.timeDoorDepartureProgress(clampedProgress)
        let fade = reduceMotion
            ? clampedProgress
            : FUMIRASpatialMotion.timeDoorFadeProgress(clampedProgress)
        let edge = FUMIRASpatialMotion.spatialPulse(departure)

        VStack {
            Spacer(minLength: 0)

            VStack(spacing: PosterSpacing.sm) {
                ZStack {
                    Circle()
                        .stroke(PosterPalette.paperWhite.opacity(0.22), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(
                            PosterPalette.bellYellow,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(PosterTypography.label)
                        .foregroundStyle(PosterPalette.paperWhite)
                }
                .frame(width: 44, height: 44)

                Text("转动，打开\(target.compactLabel)")
                    .font(PosterTypography.cardTitle)
                    .foregroundStyle(PosterPalette.paperWhite)

                Button(action: complete) {
                    Text("直接打开")
                        .font(PosterTypography.label)
                        .foregroundStyle(PosterPalette.ink)
                        .frame(minWidth: 132, minHeight: 44)
                        .background(PosterPalette.bellYellow, in: Capsule())
                }
                .buttonStyle(PosterPressStyle())
                .accessibilityIdentifier("result.reveal-now")
                .accessibilityHint("不转动设备，直接显示生成的目标时间照片")
            }
            .padding(PosterSpacing.md)
            .background(PosterPalette.cardDark)
            .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                    .stroke(PosterPalette.paperWhite.opacity(0.18), lineWidth: 1)
            }
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(PosterEffects.timeDoorEdge)
                    .frame(width: PosterSpacing.xs)
                    .padding(.vertical, PosterSpacing.sm)
                    .opacity(edge)
            }
            .rotation3DEffect(
                .degrees(-PosterMotion.timeDoorMaximumFoldDegrees * Double(departure)),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: PosterMotion.spatialPerspective
            )
            .offset(
                x: -PosterMotion.timeDoorHorizontalTravel * departure,
                y: PosterMotion.timeDoorVerticalTravel * departure
            )
            .opacity(1 - fade)
            .padding(PosterSpacing.md)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("时间门尚未完全打开")
        .accessibilityValue("\(Int(clampedProgress * 100))%")
        // This prompt lives inside a bounded photo frame. Keep it legible at
        // accessibility sizes without letting it cover the photo completely.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct RealityAlignmentOverlay: View {
    let model: AppModel
    let generated: UIImage?
    let target: TimePosition
    let close: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: CGFloat = 0.5
    @State private var previewState: PreviewState = .loading
    @State private var showsOriginalGhost = true
    @State private var didLockAlignment = false

    private var shutterAttitude: CaptureMotionSample? {
        model.temporalCapturePacket?.motion.samples.last
    }

    private var alignmentProgress: CGFloat? {
        guard let shutterAttitude else { return nil }
        return RealityAlignmentGeometry.progress(
            currentRoll: model.captureMotion.roll,
            currentPitch: model.captureMotion.pitch,
            currentYaw: model.captureMotion.yaw,
            captured: shutterAttitude
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let boundary = proxy.size.width * min(max(position, 0), 1)

            ZStack(alignment: .topLeading) {
                realitySurface
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if previewState == .live,
                   showsOriginalGhost,
                   let original = model.decodedCapturedImage {
                    Image(uiImage: original)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0)
                        .contrast(1.7)
                        .blendMode(.screen)
                        .opacity(0.14)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                comparisonImage(generated)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask {
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: boundary)
                            Rectangle()
                                .fill(Color.white)
                        }
                    }
                    .allowsHitTesting(false)

                boundaryHandle(at: boundary, height: proxy.size.height)
                    .allowsHitTesting(false)

                HStack {
                    Text(previewState == .live ? "现实 · NOW" : "原片 · NOW")
                    Spacer()
                    Text(target.compactLabel)
                }
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.paperWhite)
                .padding(.horizontal, PosterSpacing.lg)
                .padding(
                    .top,
                    PosterSpacing.xl + CameraChromeMetrics.topRowHeight
                )
                .safeAreaPadding(.top)
                .shadow(color: PosterPalette.ink.opacity(0.65), radius: 4)
                .allowsHitTesting(false)
                .zIndex(4)

                HStack(spacing: PosterSpacing.sm) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PosterPalette.paperWhite)
                            .frame(
                                width: CameraChromeMetrics.controlDiameter,
                                height: CameraChromeMetrics.controlDiameter
                            )
                            .background(PosterEffects.cameraChromeFill, in: Circle())
                    }
                    .buttonStyle(PosterPressStyle())
                    .accessibilityLabel("关闭现实对照")

                    Spacer(minLength: 0)

                    if previewState == .live,
                       model.decodedCapturedImage != nil {
                        Button {
                            showsOriginalGhost.toggle()
                        } label: {
                            Image(
                                systemName: showsOriginalGhost
                                    ? "square.dashed.inset.filled"
                                    : "square.dashed"
                            )
                            .font(PosterTypography.label)
                            .foregroundStyle(PosterPalette.paperWhite)
                            .frame(
                                width: CameraChromeMetrics.controlDiameter,
                                height: CameraChromeMetrics.controlDiameter
                            )
                            .background(PosterEffects.cameraChromeFill, in: Circle())
                        }
                        .buttonStyle(PosterPressStyle())
                        .accessibilityLabel(
                            showsOriginalGhost ? "隐藏原机位轮廓" : "显示原机位轮廓"
                        )
                    }
                }
                .padding(.horizontal, PosterSpacing.md)
                .padding(.top, PosterSpacing.sm)
                .safeAreaPadding(.top)
                .zIndex(5)

                alignmentConsole
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, PosterSpacing.md)
                    .padding(.bottom, PosterSpacing.lg)
                    .safeAreaPadding(.bottom)
                    .zIndex(5)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(boundaryGesture(width: proxy.size.width))
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("result.reality-boundary")
                    .accessibilityLabel("现实与目标时间边界")
                    .accessibilityValue("现实占 \(Int(position * 100))%")
                    .accessibilityHint("左右拖动比较现实与目标时间；上下滑动可逐级调整")
                    .accessibilityAdjustableAction(adjustBoundary)
                    .zIndex(3)
            }
        }
        .background(PosterPalette.ink)
        .task(id: scenePhase) {
            if scenePhase == .active {
                previewState = .loading
                let didStart = await model.startRealityAlignment()
                guard !Task.isCancelled else { return }
                previewState = didStart ? .live : .stillFallback
            } else {
                await model.stopRealityAlignment()
            }
        }
        .onDisappear {
            Task {
                await model.stopRealityAlignment()
            }
        }
        .onChange(of: alignmentProgress) { _, progress in
            updateAlignmentLock(progress)
        }
    }

    @ViewBuilder
    private var realitySurface: some View {
        switch previewState {
        case .loading:
            ZStack {
                comparisonImage(model.decodedCapturedImage)
                PosterPalette.ink.opacity(0.32)
                ProgressView()
                    .tint(PosterPalette.paperWhite)
            }
        case .live:
            model.cameraPreview
        case .stillFallback:
            comparisonImage(model.decodedCapturedImage)
        }
    }

    private var alignmentConsole: some View {
        HStack(spacing: PosterSpacing.md) {
            alignmentReticle

            VStack(alignment: .leading, spacing: 4) {
                Text(alignmentTitle)
                    .font(PosterTypography.cardTitle)
                    .foregroundStyle(PosterPalette.paperWhite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("NOW  ↔  \(target.compactLabel)")
                    .font(PosterTypography.caption)
                    .foregroundStyle(PosterPalette.bellYellow)
            }

            Spacer(minLength: 0)
        }
        .padding(PosterSpacing.lg)
        .background(PosterPalette.cardDark)
        .clipShape(
            RoundedRectangle(
                cornerRadius: PosterRadius.card,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: PosterRadius.card,
                style: .continuous
            )
            .stroke(PosterPalette.paperWhite.opacity(0.18), lineWidth: 1)
        }
    }

    private var alignmentReticle: some View {
        ZStack {
            Circle()
                .stroke(PosterPalette.paperWhite.opacity(0.24), lineWidth: 2)
            Circle()
                .trim(from: 0, to: alignmentProgress ?? 0)
                .stroke(
                    didLockAlignment
                        ? PosterPalette.bellYellow
                        : PosterPalette.paperWhite,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: didLockAlignment ? "scope" : "viewfinder")
                .font(PosterTypography.caption)
                .foregroundStyle(
                    didLockAlignment
                        ? PosterPalette.bellYellow
                        : PosterPalette.paperWhite
                )
        }
        .frame(width: 44, height: 44)
        .animation(
            reduceMotion ? nil : PosterMotion.interaction,
            value: didLockAlignment
        )
        .accessibilityHidden(true)
    }

    private var alignmentTitle: String {
        switch previewState {
        case .loading:
            return "正在打开现实"
        case .stillFallback:
            return "拖动，看时间差"
        case .live:
            if didLockAlignment {
                return "机位已对齐"
            }
            return "拖动，看时间差"
        }
    }

    private func boundaryHandle(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(PosterPalette.paperWhite)
                .frame(width: 2, height: height)
                .shadow(color: PosterPalette.ink.opacity(0.34), radius: 5)

            Capsule()
                .fill(PosterPalette.paperWhite)
                .frame(width: 28, height: 52)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(PosterTypography.caption)
                        .foregroundStyle(PosterPalette.ink)
                }
                .shadow(color: PosterPalette.ink.opacity(0.28), radius: 6, y: 2)
        }
        .position(x: x, y: height * 0.5)
    }

    private func boundaryGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                position = min(max(value.location.x / max(width, 1), 0), 1)
            }
    }

    private func adjustBoundary(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            position = min(position + 0.1, 1)
        case .decrement:
            position = max(position - 0.1, 0)
        @unknown default:
            break
        }
    }

    private func updateAlignmentLock(_ progress: CGFloat?) {
        let value = progress ?? 0
        if value >= 0.9, !didLockAlignment {
            didLockAlignment = true
            model.playRealityAlignmentLockHaptic()
        } else if value < 0.68 {
            didLockAlignment = false
        }
    }

    @ViewBuilder
    private func comparisonImage(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            PosterPalette.skySoft
        }
    }

    private enum PreviewState: Equatable {
        case loading
        case live
        case stillFallback
    }
}

enum RealityAlignmentGeometry {
    static func progress(
        currentRoll: Double,
        currentPitch: Double,
        currentYaw: Double,
        captured: CaptureMotionSample
    ) -> CGFloat {
        let roll = angularDistance(currentRoll, captured.roll)
        let pitch = angularDistance(currentPitch, captured.pitch)
        let yaw = angularDistance(currentYaw, captured.yaw)
        let weightedDistance = sqrt(
            roll * roll
                + pitch * pitch
                + yaw * yaw * 0.45
        )
        return CGFloat(min(max(1 - weightedDistance / 0.24, 0), 1))
    }

    static func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        var angle = lhs - rhs
        while angle > .pi { angle -= .pi * 2 }
        while angle < -.pi { angle += .pi * 2 }
        return abs(angle)
    }
}

enum ResultLayoutGeometry {
    static let accessiblePhotoMaximumHeight: CGFloat = 520
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
                .background(PosterPalette.cardActive)
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

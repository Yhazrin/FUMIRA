import AVKit
import PhotosUI
import SwiftUI

struct ViewfinderView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = CameraCompositionGeometry.layout(
                aspectRatio: model.cameraAspectRatio,
                in: proxy.size
            )
            let cardShape = UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: layout.cornerRadius,
                    bottomTrailing: layout.cornerRadius,
                    topTrailing: 0
                ),
                style: .continuous
            )

            ZStack {
                // The blue surface is the physical camera body. The preview is
                // a separate top-anchored card whose lower edge moves as the
                // user pinches between capture ratios.
                PosterPalette.cameraBody
                    .ignoresSafeArea()

                cardShape
                    .fill(PosterPalette.ink)
                    .frame(
                        width: layout.heroFrame.width,
                        height: layout.heroFrame.height
                    )
                    .position(
                        x: layout.heroFrame.midX,
                        y: layout.heroFrame.midY
                    )

                model.cameraPreview
                    .frame(
                        width: layout.heroFrame.width,
                        height: layout.heroFrame.height
                    )
                    .clipped()
                    .clipShape(cardShape)
                    .position(
                        x: layout.heroFrame.midX,
                        y: layout.heroFrame.midY
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                if model.isCameraGridEnabled {
                    CameraCompositionGrid(
                        frame: layout.heroFrame,
                        cornerRadius: layout.cornerRadius
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(
                Self.compositionMorphAnimation(reduceMotion: reduceMotion),
                value: model.cameraAspectRatio
            )
            .animation(
                Self.compositionMorphAnimation(reduceMotion: reduceMotion),
                value: model.isCameraGridEnabled
            )
        }
        .ignoresSafeArea()
    }

    /// Keeps the shade and grid moving in one local geometry space.
    fileprivate static func compositionMorphAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.cameraComposition
    }
}

/// Top + bottom camera chrome, hosted above the viewfinder stage by ``RootView``.
struct ViewfinderChromeOverlay: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsAreReady = false
    @State private var albumPickerItem: PhotosPickerItem?
    @State private var captureOrientation: UIDeviceOrientation = .portrait
    @State private var aspectGestureStartRatio: CameraAspectRatio?
    @State private var isAspectRatioBadgeVisible = false
    @State private var aspectBadgeDismissTask: Task<Void, Never>?
    @State private var systemTopInset: CGFloat = 0
    @State private var systemBottomInset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let compositionFrame = CameraCompositionGeometry.layout(
                aspectRatio: model.cameraAspectRatio,
                in: proxy.size
            ).heroFrame
            let controlPlacement = CameraCompositionGeometry.controlPlacement(
                below: compositionFrame,
                in: proxy.size,
                bottomSafeAreaInset: systemBottomInset
            )
            let topChromeTopY = max(
                compositionFrame.minY + PosterSpacing.sm,
                systemTopInset + PosterSpacing.sm
            )
            let feedbackCenterY = topChromeTopY
                + CameraChromeMetrics.topRowHeight
                + PosterSpacing.sm
                + CameraChromeMetrics.compactFeedbackHeight * 0.5

            ZStack(alignment: .top) {
                // The interaction surface now matches the visible camera card,
                // so a pinch belongs to the viewfinder rather than the blue body.
                Color.clear
                    .frame(
                        width: compositionFrame.width,
                        height: compositionFrame.height
                    )
                    .contentShape(
                        UnevenRoundedRectangle(
                            cornerRadii: RectangleCornerRadii(
                                topLeading: 0,
                                bottomLeading: CameraCompositionGeometry
                                    .compositionCornerRadius(for: compositionFrame),
                                bottomTrailing: CameraCompositionGeometry
                                    .compositionCornerRadius(for: compositionFrame),
                                topTrailing: 0
                            ),
                            style: .continuous
                        )
                    )
                    .position(
                        x: compositionFrame.midX,
                        y: compositionFrame.midY
                    )
                    .simultaneousGesture(aspectRatioGesture)
                    .simultaneousGesture(
                        subjectAnchorGesture(
                            in: CGRect(origin: .zero, size: compositionFrame.size)
                        )
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("viewfinder.aspect-control")
                    .accessibilityLabel("取景画幅")
                    .accessibilityValue(model.cameraAspectRatio.label)
                    .accessibilityHint("双指捏合调整画幅；单指轻点选择时间主体")
                    .accessibilityAdjustableAction(adjustAspectRatio)
                    .accessibilityAction(named: Text("将画面中心设为时间主体")) {
                        model.selectNarrativeSubject(
                            at: CGPoint(x: 0.5, y: 0.5)
                        )
                    }
                    .accessibilityAction(named: Text("清除时间主体")) {
                        model.clearNarrativeSubject()
                    }

                VStack(spacing: 0) {
                    topChrome
                        .frame(width: compositionFrame.width)
                        .padding(.top, topChromeTopY)
                        .allowsHitTesting(controlsAreReady)

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }

                bottomChrome
                    .frame(width: proxy.size.width - PosterSpacing.md * 2)
                    .position(
                        x: proxy.size.width * 0.5,
                        y: controlPlacement.centerY
                    )
                    .shadow(
                        color: controlPlacement.overlaysPreview
                            ? PosterEffects.cameraFloatingWaveShadow
                            : .clear,
                        radius: PosterEffects.cameraFloatingWaveShadowRadius,
                        y: PosterEffects.cameraFloatingWaveShadowOffset
                    )
                    .allowsHitTesting(controlsAreReady)

                TimeAnchorReticle(motion: model.captureMotion)
                    .frame(
                        width: compositionFrame.width,
                        height: compositionFrame.height
                    )
                    .position(
                        x: compositionFrame.midX,
                        y: compositionFrame.midY
                    )
                    .allowsHitTesting(false)

                if let anchor = model.narrativeSubjectAnchor {
                    NarrativeAnchorMarker()
                        .position(
                            x: markerCoordinate(
                                normalized: anchor.normalizedX,
                                lowerBound: compositionFrame.minX,
                                extent: compositionFrame.width
                            ),
                            y: markerCoordinate(
                                normalized: anchor.normalizedY,
                                lowerBound: compositionFrame.minY,
                                extent: compositionFrame.height
                            )
                        )
                        .animation(
                            reduceMotion ? nil : PosterMotion.interaction,
                            value: anchor
                        )
                }

                if isAspectRatioBadgeVisible {
                    aspectRatioBadge
                        .position(
                            x: compositionFrame.midX,
                            y: compositionFrame.maxY - PosterSpacing.xl
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(
                            .opacity.combined(
                                with: .scale(
                                    scale: PosterMotion.cameraAspectBadgeTransitionScale
                                )
                            )
                        )
                        .zIndex(5)
                }

                if let feedback = model.cameraActivityFeedback {
                    liveActivityFeedback(feedback)
                        .frame(maxWidth: compositionFrame.width - PosterSpacing.xl * 2)
                        .position(
                            x: compositionFrame.midX,
                            y: feedbackCenterY
                        )
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                        )
                        .zIndex(4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cameraHardwareCapture(isEnabled: controlsAreReady && !model.isPipelineBusy) {
            Task { await model.capture() }
        }
        .task {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            syncSystemSafeAreaInsets()
            updateCaptureOrientation(UIDevice.current.orientation)
            try? await Task.sleep(for: PosterMotion.cameraInputGuard)
            guard !Task.isCancelled else { return }
            controlsAreReady = true
            #if DEBUG
            await runDebugCompositionAuditIfNeeded()
            #endif
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
        ) { _ in
            syncSystemSafeAreaInsets()
            updateCaptureOrientation(UIDevice.current.orientation)
        }
        .onChange(of: albumPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importAlbumItem(newItem)
                albumPickerItem = nil
            }
        }
        .onDisappear {
            aspectBadgeDismissTask?.cancel()
        }
        .animation(
            reduceMotion ? nil : PosterMotion.interaction,
            value: model.cameraActivityFeedback
        )
        .animation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : PosterMotion.interaction,
            value: isAspectRatioBadgeVisible
        )
    }

    private var aspectRatioGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let start = aspectGestureStartRatio ?? model.cameraAspectRatio
                aspectGestureStartRatio = start
                aspectBadgeDismissTask?.cancel()
                isAspectRatioBadgeVisible = true

                model.selectCameraAspectRatio(
                    CameraAspectRatio.aspectRatio(
                        afterPinchMagnification: value.magnification,
                        startingAt: start
                    )
                )
            }
            .onEnded { _ in
                aspectGestureStartRatio = nil
                scheduleAspectBadgeDismissal()
            }
    }

    private func scheduleAspectBadgeDismissal() {
        aspectBadgeDismissTask?.cancel()
        aspectBadgeDismissTask = Task { @MainActor in
            try? await Task.sleep(for: PosterMotion.cameraAspectBadgeHold)
            guard !Task.isCancelled else { return }
            isAspectRatioBadgeVisible = false
        }
    }

    private func subjectAnchorGesture(in compositionFrame: CGRect) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                guard
                    compositionFrame.width > 0,
                    compositionFrame.height > 0,
                    compositionFrame.contains(value.location)
                else {
                    return
                }
                model.selectNarrativeSubject(
                    at: CGPoint(
                        x: (value.location.x - compositionFrame.minX)
                            / compositionFrame.width,
                        y: (value.location.y - compositionFrame.minY)
                            / compositionFrame.height
                    )
                )
            }
    }

    private func markerCoordinate(
        normalized: Double,
        lowerBound: CGFloat,
        extent: CGFloat
    ) -> CGFloat {
        let unclamped = lowerBound + CGFloat(normalized) * extent
        return min(
            max(unclamped, lowerBound + PosterSpacing.xl),
            max(
                lowerBound + extent - PosterSpacing.xl,
                lowerBound + PosterSpacing.xl
            )
        )
    }

    private var aspectRatioBadge: some View {
        Text(model.cameraAspectRatio.label)
            .font(.callout.weight(.bold))
            .foregroundStyle(PosterEffects.cameraChromeSolidForeground)
            .padding(.horizontal, PosterSpacing.md)
            .frame(minHeight: CameraChromeMetrics.compactFeedbackHeight)
            .background(PosterEffects.cameraChromeSolidFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(PosterEffects.cameraChromeSolidStroke, lineWidth: 1)
            }
            .shadow(
                color: PosterEffects.control,
                radius: PosterEffects.cameraChromeFeedbackShadowRadius,
                y: PosterEffects.cameraChromeFeedbackShadowOffset
            )
    }

    private func liveActivityFeedback(_ text: String) -> some View {
        Label(text, systemImage: "wave.3.right.circle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(PosterEffects.cameraChromeSolidForeground)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, PosterSpacing.md)
            .frame(minHeight: CameraChromeMetrics.compactFeedbackHeight)
            .background(PosterEffects.cameraChromeSolidFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(PosterEffects.cameraChromeSolidStroke, lineWidth: 1)
            }
            .shadow(
                color: PosterEffects.control,
                radius: PosterEffects.cameraChromeFeedbackShadowRadius,
                y: PosterEffects.cameraChromeFeedbackShadowOffset
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("viewfinder.live-activity-feedback")
    }

    private func adjustAspectRatio(_ direction: AccessibilityAdjustmentDirection) {
        let magnification: CGFloat
        switch direction {
        case .increment:
            magnification = 1.16
        case .decrement:
            magnification = 1 / 1.16
        @unknown default:
            return
        }

        model.selectCameraAspectRatio(
            CameraAspectRatio.aspectRatio(
                afterPinchMagnification: magnification,
                startingAt: model.cameraAspectRatio
            )
        )
    }

    /// Only in-app camera actions live in this row. Live camera state belongs
    /// to the system Dynamic Island through the ActivityKit widget extension.
    @ViewBuilder
    private var topChrome: some View {
        HStack {
            albumPickerButton
            Spacer(minLength: 0)
            CameraChromeButton(
                systemImage: "dot.radiowaves.left.and.right",
                rotation: chromeRotation,
                accessibilityLabelText: "显示实时相机状态",
                accessibilityHintText: "在系统灵动岛显示取景状态；长按可展开控制"
            ) {
                Task { await model.triggerCameraLiveActivity() }
            }
        }
        .padding(.horizontal, PosterSpacing.md)
        .frame(height: CameraChromeMetrics.topRowHeight, alignment: .top)
    }

    #if DEBUG
    private func runDebugCompositionAuditIfNeeded() async {
        if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_AUTO_CAPTURE"] == "trigger" {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await model.capture()
            return
        }

        if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_LIVE_ACTIVITY"] == "trigger" {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await model.triggerCameraLiveActivity()
            return
        }

        guard ProcessInfo.processInfo.environment["FUMIRA_AUDIT_CAMERA_MORPH"] == "fullscreen"
        else {
            return
        }

        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        isAspectRatioBadgeVisible = true
        withAnimation(ViewfinderView.compositionMorphAnimation(reduceMotion: reduceMotion)) {
            model.selectCameraAspectRatio(.fullScreen)
        }
        scheduleAspectBadgeDismissal()
    }
    #endif

    /// Counter-rotates chrome so labels stay gravity-upright while the app stays portrait-locked.
    private var chromeRotation: Angle {
        switch captureOrientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        case .portraitUpsideDown:
            return .degrees(180)
        default:
            return .zero
        }
    }

    /// Bottom: shutter and time selection are one morphing control.
    private var bottomChrome: some View {
        ShutterWaveTimeRail(
            value: model.selectedTime.normalized,
            onDetent: model.playTimeDetent,
            onChange: { normalized in
                model.updateTime(normalized: normalized)
            },
            onShutterPress: model.playShutterPressHaptic,
            onCapture: {
                Task { await model.capture() }
            },
            chromeRotation: chromeRotation
        )
        .padding(.bottom, PosterSpacing.sm)
        .accessibilityIdentifier("viewfinder.shutter-wave")
    }

    private var albumPickerButton: some View {
        let iconRotation = chromeRotation

        return PhotosPicker(
            selection: $albumPickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            CameraChromeGlyph(
                systemImage: "photo.on.rectangle",
                rotation: iconRotation
            )
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel("从相册导入")
        .accessibilityHint("选择一张照片进入时间相机管线")
        .disabled(model.isPipelineBusy)
    }

    private func importAlbumItem(_ item: PhotosPickerItem) async {
        do {
            guard let raw = try await item.loadTransferable(type: AlbumImageData.self) else {
                model.lastErrorMessage = PhotoImportAdapter.ImportError.invalidImage.localizedDescription
                return
            }
            await model.importPhoto(imageData: raw.data)
        } catch {
            model.lastErrorMessage = error.localizedDescription
        }
    }

    private func updateCaptureOrientation(_ orientation: UIDeviceOrientation) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_CAMERA_ORIENTATION"] == "landscapeLeft" {
            captureOrientation = .landscapeLeft
            return
        }
        #endif

        guard orientation == .portrait
                || orientation == .portraitUpsideDown
                || orientation == .landscapeLeft
                || orientation == .landscapeRight
        else {
            return
        }

        if reduceMotion {
            captureOrientation = orientation
        } else {
            withAnimation(PosterMotion.decelerate) {
                captureOrientation = orientation
            }
        }
    }

    private func syncSystemSafeAreaInsets() {
        let insets = CameraChromeMetrics.activeWindowSafeAreaInsets
        systemTopInset = insets.top
        systemBottomInset = insets.bottom
    }

}

/// PhotosPicker Transferable for JPEG / PNG / HEIC library bytes.
private struct AlbumImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            AlbumImageData(data: data)
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            AlbumImageData(data: data)
        }
        DataRepresentation(importedContentType: .png) { data in
            AlbumImageData(data: data)
        }
        DataRepresentation(importedContentType: .heic) { data in
            AlbumImageData(data: data)
        }
    }
}

private extension View {
    @ViewBuilder
    func cameraHardwareCapture(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            onCameraCaptureEvent(
                isEnabled: isEnabled,
                primaryAction: { event in
                    guard event.phase == .ended else { return }
                    action()
                },
                secondaryAction: { _ in }
            )
        } else {
            self
        }
    }
}

private struct CameraCompositionGrid: View {
    let frame: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for step in 1...2 {
                let x = size.width * CGFloat(step) / 3
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))

                let y = size.height * CGFloat(step) / 3
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(
                path,
                with: .color(PosterPalette.paperWhite.opacity(0.32)),
                lineWidth: 1
            )
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: cornerRadius,
                    bottomTrailing: cornerRadius,
                    topTrailing: 0
                ),
                style: .continuous
            )
        )
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }
}

#Preview("Live layout") {
    struct PreviewWrapper: View {
        @Namespace private var namespace
        private let model = PreviewFixtures.model(phase: .viewfinder)

        var body: some View {
            ZStack {
                ViewfinderView(model: model, namespace: namespace)
                ViewfinderChromeOverlay(model: model)
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Scrubbed time") {
    struct PreviewWrapper: View {
        @Namespace private var namespace
        private let model = PreviewFixtures.model(phase: .viewfinder, time: 0.35)

        var body: some View {
            ZStack {
                ViewfinderView(model: model, namespace: namespace)
                ViewfinderChromeOverlay(model: model)
            }
        }
    }
    return PreviewWrapper()
}

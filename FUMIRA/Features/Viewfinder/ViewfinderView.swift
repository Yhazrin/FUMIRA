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
                ClayPalette.orange
                    .ignoresSafeArea()
                    .overlay {
                        ClayNoiseTexture(opacity: 0.08)
                            .ignoresSafeArea()
                    }

                cardShape
                    .fill(ClayPalette.charcoal)
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
    @State private var railIntroProgress: CGFloat = 0
    @State private var albumPickerItem: PhotosPickerItem?
    @State private var captureOrientation: UIDeviceOrientation = .portrait
    @State private var aspectGestureStartRatio: CameraAspectRatio?
    @State private var isAspectRatioBadgeVisible = false
    @State private var aspectBadgeDismissTask: Task<Void, Never>?
    @State private var systemTopInset: CGFloat = 0
    @State private var systemBottomInset: CGFloat = 0
    @State private var isSettingsPresented = false

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
                compositionFrame.minY + ClaySpacing.sm,
                systemTopInset + ClaySpacing.sm
            )
            let feedbackCenterY = topChromeTopY
                + CameraChromeMetrics.topRowHeight
                + ClaySpacing.sm
                + CameraChromeMetrics.compactFeedbackHeight * 0.5

            ZStack(alignment: .top) {
                // Interaction surface matches the visible camera card. Vertical
                // aspect drags only arm when they begin in the lower band.
                // Subject following comes from the camera service, not taps.
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
                    .simultaneousGesture(
                        aspectRatioGesture(in: compositionFrame.size)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("viewfinder.aspect-control")
                    .accessibilityLabel("取景画幅与自动主体跟焦")
                    .accessibilityValue(model.cameraAspectRatio.label)
                    .accessibilityHint("在取景框下侧上下滑动调整画幅；相机会自动识别并跟随主体")
                    .accessibilityAdjustableAction(adjustAspectRatio)

                VStack(spacing: 0) {
                    topChrome
                        .frame(width: compositionFrame.width)
                        .padding(.top, topChromeTopY)
                        .allowsHitTesting(controlsAreReady)

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }

                bottomChrome
                    .frame(width: proxy.size.width - ClaySpacing.sm * 2)
                    .waveRailFlatIntro(
                        progress: railIntroProgress,
                        reduceMotion: reduceMotion
                    )
                    .position(
                        x: proxy.size.width * 0.5,
                        y: controlPlacement.centerY
                    )
                    .shadow(
                        color: controlPlacement.overlaysPreview
                            ? ClayPalette.charcoal.opacity(0.24)
                            : .clear,
                        radius: 10,
                        y: 3
                    )
                    .allowsHitTesting(controlsAreReady && railIntroProgress > 0.85)

                if let subject = model.cameraTrackedSubject {
                    let subjectFrame = trackedSubjectFrame(
                        subject,
                        in: compositionFrame
                    )
                    SubjectTrackingReticle(confidence: subject.confidence)
                        .frame(
                            width: subjectFrame.width,
                            height: subjectFrame.height
                        )
                        .position(x: subjectFrame.midX, y: subjectFrame.midY)
                        .animation(
                            reduceMotion ? nil : PosterMotion.subjectTracking,
                            value: subject.normalizedBounds
                        )
                }

                if isAspectRatioBadgeVisible {
                    aspectRatioBadge
                        .position(
                            x: compositionFrame.midX,
                            y: compositionFrame.maxY - ClaySpacing.xxxl
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
                        .frame(maxWidth: compositionFrame.width - ClaySpacing.xxxl * 2)
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
            model.beginCameraSubjectTracking()
            syncSystemSafeAreaInsets()
            updateCaptureOrientation(UIDevice.current.orientation)
            await playChromeEntrance()
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
            model.endCameraSubjectTracking()
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
        // Chrome is an invisible overlay — extending into the safe area
        // guarantees the GeometryReader reports the full-screen size so
        // every positioned control (top row, shutter rail) lands exactly
        // where ViewfinderView's own full-bleed preview expects it.
        .ignoresSafeArea()
    }

    /// Lower fraction of the composition card that accepts vertical aspect
    /// drags — matching “push the card's bottom edge” rather than a full-frame
    /// pan that would fight subject taps higher up.
    private static let aspectGestureBandFraction: CGFloat = 0.38

    private func aspectRatioGesture(in compositionSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let lowerBandMinY = compositionSize.height
                    * (1 - Self.aspectGestureBandFraction)
                if aspectGestureStartRatio == nil {
                    guard value.startLocation.y >= lowerBandMinY else { return }
                    aspectGestureStartRatio = model.cameraAspectRatio
                }
                guard let start = aspectGestureStartRatio else { return }

                aspectBadgeDismissTask?.cancel()
                isAspectRatioBadgeVisible = true
                model.selectCameraAspectRatio(
                    CameraAspectRatio.aspectRatio(
                        afterVerticalTranslation: value.translation.height,
                        startingAt: start
                    )
                )
            }
            .onEnded { _ in
                guard aspectGestureStartRatio != nil else { return }
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

    private func trackedSubjectFrame(
        _ subject: CameraTrackedSubject,
        in compositionFrame: CGRect
    ) -> CGRect {
                let minimumExtent = ClaySpacing.xxl + ClaySpacing.xxs
        let proposedWidth = CGFloat(subject.normalizedWidth)
            * compositionFrame.width
        let proposedHeight = CGFloat(subject.normalizedHeight)
            * compositionFrame.height
        // Compact 1:1 lock — smaller than the raw Vision core so corner marks
        // read as a quiet focus accent, not a full-scene selection.
        let proposedSide = max(proposedWidth, proposedHeight) * 0.54
        let maxSide = min(compositionFrame.width, compositionFrame.height) * 0.28
        let side = min(max(proposedSide, minimumExtent), maxSide)
        let centerX = compositionFrame.minX
            + subject.center.x * compositionFrame.width
        let centerY = compositionFrame.minY
            + subject.center.y * compositionFrame.height
        let originX = min(
            max(centerX - side * 0.5, compositionFrame.minX),
            compositionFrame.maxX - side
        )
        let originY = min(
            max(centerY - side * 0.5, compositionFrame.minY),
            compositionFrame.maxY - side
        )
        return CGRect(
            x: originX,
            y: originY,
            width: side,
            height: side
        )
    }

    private var aspectRatioBadge: some View {
        Text(model.cameraAspectRatio.label)
            .font(.callout.weight(.bold))
            .foregroundStyle(ClayPalette.warmWhite)
            .padding(.horizontal, ClaySpacing.lg)
            .frame(minHeight: CameraChromeMetrics.compactFeedbackHeight)
            .background(ClayPalette.orangeRim, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(ClayPalette.orange.opacity(0.72), lineWidth: 1)
            }
            .shadow(
                color: ClayShadow.small.color,
                radius: ClayShadow.small.radius,
                y: ClayShadow.small.y
            )
    }

    private func liveActivityFeedback(_ text: String) -> some View {
        Label(text, systemImage: "wave.3.right.circle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(ClayPalette.warmWhite)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, ClaySpacing.lg)
            .frame(minHeight: CameraChromeMetrics.compactFeedbackHeight)
            .background(ClayPalette.orangeRim, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(ClayPalette.orange.opacity(0.72), lineWidth: 1)
            }
            .shadow(
                color: ClayShadow.small.color,
                radius: ClayShadow.small.radius,
                y: ClayShadow.small.y
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("viewfinder.live-activity-feedback")
    }

    private func adjustAspectRatio(_ direction: AccessibilityAdjustmentDirection) {
        let translation: CGFloat
        switch direction {
        case .increment:
            // Expand toward full frame — same direction as dragging down.
            translation = CameraAspectRatio.verticalAspectStepDistance
        case .decrement:
            // Tighten toward square — same direction as dragging up.
            translation = -CameraAspectRatio.verticalAspectStepDistance
        @unknown default:
            return
        }

        model.selectCameraAspectRatio(
            CameraAspectRatio.aspectRatio(
                afterVerticalTranslation: translation,
                startingAt: model.cameraAspectRatio
            )
        )
    }

    /// Only in-app camera actions live in this row.
    @ViewBuilder
    private var topChrome: some View {
        HStack {
            albumPickerButton
            Spacer(minLength: 0)
            CameraChromeButton(
                systemImage: "gearshape",
                isEnabled: true,
                rotation: chromeRotation,
                accessibilityLabelText: "设置",
                accessibilityHintText: "打开设置页面"
            ) {
                isSettingsPresented = true
            }
        }
        .padding(.horizontal, ClaySpacing.lg)
        .frame(height: CameraChromeMetrics.topRowHeight, alignment: .center)
        .sheet(isPresented: $isSettingsPresented) {
            ViewfinderSettingsView(model: model)
        }
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
        .accessibilityIdentifier("viewfinder.shutter-wave")
    }

    /// Viewfinder card slides on its own. The rail stays in deck position and
    /// constructs itself with a flat hairline → rise → settle beat.
    private func playChromeEntrance() async {
        railIntroProgress = 0
        controlsAreReady = false

        guard !reduceMotion else {
            railIntroProgress = 1
            try? await Task.sleep(for: PosterMotion.cameraInputGuard)
            guard !Task.isCancelled else { return }
            controlsAreReady = true
            return
        }

        try? await Task.sleep(for: PosterMotion.cameraRailIntroDelay)
        guard !Task.isCancelled else { return }
        withAnimation(PosterMotion.cameraRailIntro) {
            railIntroProgress = 1
        }

        try? await Task.sleep(for: PosterMotion.cameraInputGuard)
        guard !Task.isCancelled else { return }
        controlsAreReady = true
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
                with: .color(ClayPalette.warmWhite.opacity(0.32)),
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

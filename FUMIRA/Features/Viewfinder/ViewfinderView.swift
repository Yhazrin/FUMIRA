import AVKit
import PhotosUI
import SwiftUI

struct ViewfinderView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoomGestureStartFactor: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let layout = CameraCompositionGeometry.layout(
                aspectRatio: model.cameraAspectRatio,
                in: proxy.size
            )

            ZStack {
                // One full-screen preview is the source for both the clear crop
                // and its translucent surround. Duplicating the preview at two
                // aspect-fill sizes makes the scene discontinuous at the crop.
                model.cameraPreview
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                CameraCompositionGlass(
                    cropFrame: layout.heroFrame,
                    cornerRadius: layout.cornerRadius,
                    drawsFrame: layout.cropFrame != nil
                )

                if model.isCameraGridEnabled {
                    CameraCompositionGrid(
                        frame: layout.heroFrame,
                        cornerRadius: layout.cornerRadius
                    )
                }

                // Status-bar scrim only — chrome contrast lives on the controls.
                LinearGradient(
                    colors: [PosterPalette.ink.opacity(0.22), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 104)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
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
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    guard model.supportsCameraZoom else { return }
                    let start = zoomGestureStartFactor ?? model.cameraZoomSnapshot.factor
                    if zoomGestureStartFactor == nil {
                        zoomGestureStartFactor = start
                    }
                    model.setCameraZoomFactor(start * value.magnification)
                }
                .onEnded { _ in
                    zoomGestureStartFactor = nil
                }
        )
        // RootView hosts the chrome as a sibling above the preview and shade.
        .accessibilityElement(children: .contain)
        .accessibilityHidden(true)
    }

    /// Keeps the shade and grid moving in one local geometry space.
    fileprivate static func compositionMorphAnimation(reduceMotion: Bool) -> Animation? {
        .posterHeroMorph(reduceMotion: reduceMotion)
    }
}

/// Top + bottom camera chrome, hosted above the viewfinder stage by ``RootView``.
struct ViewfinderChromeOverlay: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsAreReady = false
    @State private var albumPickerItem: PhotosPickerItem?
    @State private var captureOrientation: UIDeviceOrientation = .portrait

    var body: some View {
        VStack(spacing: 0) {
            topChrome
                .padding(.horizontal, PosterSpacing.md)
                .padding(.top, PosterSpacing.sm)
                .allowsHitTesting(controlsAreReady)

            Spacer(minLength: 0)
                .allowsHitTesting(false)

            bottomChrome
                .padding(.horizontal, PosterSpacing.xs)
                .padding(.bottom, PosterSpacing.md)
                .safeAreaPadding(.bottom)
                .allowsHitTesting(controlsAreReady)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cameraHardwareCapture(isEnabled: controlsAreReady && !model.isPipelineBusy) {
            Task { await model.capture() }
        }
        .task {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
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
            updateCaptureOrientation(UIDevice.current.orientation)
        }
        .onChange(of: albumPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importAlbumItem(newItem)
                albumPickerItem = nil
            }
        }
    }

    /// One capsule per side. The trailing capsule requests the real ActivityKit
    /// system surface; no in-app panel imitates the Dynamic Island.
    private var topChrome: some View {
        HStack {
            albumPickerButton

            Spacer(minLength: 0)

            Button {
                Task { await model.triggerCameraLiveActivity() }
            } label: {
                Image(systemName: "camera.aperture")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .rotationEffect(chromeRotation)
                    .frame(
                        width: CameraChromeMetrics.islandSideCapsuleWidth,
                        height: CameraChromeMetrics.islandSideCapsuleHeight
                    )
                    .background(PosterEffects.cameraChromeFill)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(PosterPalette.cameraShutterBlue, lineWidth: 1)
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(PosterPressStyle())
            .accessibilityLabel("展开灵动岛相机控制")
            .accessibilityValue("当前倍率 \(formattedZoom)")
            .accessibilityHint("触发系统实时活动；长按灵动岛也可展开控制")
        }
        .frame(maxWidth: .infinity)
        .frame(height: CameraChromeMetrics.topRowHeight, alignment: .top)
    }

    #if DEBUG
    private func runDebugCompositionAuditIfNeeded() async {
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
        withAnimation(ViewfinderView.compositionMorphAnimation(reduceMotion: reduceMotion)) {
            model.selectCameraAspectRatio(.fullScreen)
        }
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
    }

    private var albumPickerButton: some View {
        let iconRotation = chromeRotation

        return PhotosPicker(
            selection: $albumPickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
                Image(systemName: "photo.on.rectangle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .rotationEffect(iconRotation)
                .frame(
                    width: CameraChromeMetrics.islandSideCapsuleWidth,
                    height: CameraChromeMetrics.islandSideCapsuleHeight
                )
                .background(PosterEffects.cameraChromeFill)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(PosterEffects.cameraChromeStroke, lineWidth: 1)
                }
                .contentShape(Capsule())
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

    private var formattedZoom: String {
        let value = max(model.cameraZoomSnapshot.displayFactor, 0)
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))×"
        }
        return String(format: "%.1f×", value)
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

/// Adaptive frosted surround over the single continuous live preview.
private struct CameraCompositionGlass: View {
    let cropFrame: CGRect
    let cornerRadius: CGFloat
    let drawsFrame: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            surroundShape
                .fill(.ultraThinMaterial, style: FillStyle(eoFill: true))

            surroundShape
                .fill(adaptiveTint, style: FillStyle(eoFill: true))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(PosterEffects.cameraCompositionStroke, lineWidth: 1)
                .frame(width: cropFrame.width, height: cropFrame.height)
                .position(x: cropFrame.midX, y: cropFrame.midY)
                .opacity(drawsFrame ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var surroundShape: CompositionSurroundShape {
        CompositionSurroundShape(
            cropFrame: cropFrame,
            cornerRadius: cornerRadius
        )
    }

    private var adaptiveTint: Color {
        colorScheme == .dark
            ? PosterEffects.cameraCompositionDarkTint
            : PosterEffects.cameraCompositionLightTint
    }
}

private struct CompositionSurroundShape: Shape {
    var cropFrame: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(cropFrame.origin.x, cropFrame.origin.y),
                AnimatablePair(
                    AnimatablePair(cropFrame.size.width, cropFrame.size.height),
                    cornerRadius
                )
            )
        }
        set {
            cropFrame = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first.first,
                height: newValue.second.first.second
            )
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: cropFrame,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
        return path
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
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

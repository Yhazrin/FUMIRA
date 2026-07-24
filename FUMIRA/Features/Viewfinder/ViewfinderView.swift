import PhotosUI
import SwiftUI

struct ViewfinderView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsAreReady = false
    @State private var shutterFlash = 0.0
    @State private var albumPickerItem: PhotosPickerItem?
    @State private var captureOrientation: UIDeviceOrientation = .portrait

    var body: some View {
        ZStack {
            preview
                .ignoresSafeArea()

            CameraCompositionOverlay(
                aspectRatio: model.cameraAspectRatio,
                showsGrid: model.isCameraGridEnabled
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Only the status-bar area needs a scrim. The time rail and camera
            // controls carry their own contrast, so a full-width bottom layer
            // would read as a grey rectangle over the live view.
            LinearGradient(
                colors: [PosterPalette.ink.opacity(0.22), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 104)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(.top, PosterSpacing.sm)
                    .allowsHitTesting(controlsAreReady)

                Spacer(minLength: 0)

                bottomChrome
                    .padding(.horizontal, PosterSpacing.xs)
                    .padding(.bottom, PosterSpacing.md)
                    .allowsHitTesting(controlsAreReady)
            }

            PosterEffects.cameraFlashWash
                .opacity(shutterFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .task {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateCaptureOrientation(UIDevice.current.orientation)
            await model.refreshCameraControls()
            try? await Task.sleep(for: PosterMotion.cameraInputGuard)
            guard !Task.isCancelled else { return }
            controlsAreReady = true
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

    /// Top: flash / flip · album import · aspect ratio.
    /// Each control rotates in place so it stays upright when the phone is sideways.
    private var topChrome: some View {
        HStack(alignment: .center, spacing: PosterSpacing.sm) {
            HStack(spacing: PosterSpacing.sm) {
                if model.supportsCameraFlash {
                    CameraChromeButton(
                        systemImage: model.cameraControlSnapshot.flashMode.systemImageName,
                        accessibilityLabelText: model.cameraControlSnapshot.flashMode.accessibilityLabel,
                        accessibilityHintText: "循环切换闪光灯模式"
                    ) {
                        Task { await model.cycleFlashMode() }
                    }
                    .rotationEffect(chromeRotation)
                }

                if model.canSwitchCamera {
                    CameraChromeButton(
                        systemImage: "arrow.triangle.2.circlepath",
                        accessibilityLabelText: model.cameraControlSnapshot.lensPosition == .front
                            ? "切换到后置摄像头"
                            : "切换到前置摄像头",
                        accessibilityHintText: "翻转前后摄像头"
                    ) {
                        Task { await model.switchCameraLens() }
                    }
                    .rotationEffect(chromeRotation)
                }

                albumPickerButton
                    .rotationEffect(chromeRotation)
            }

            Spacer(minLength: PosterSpacing.sm)

            aspectRatioMenu
                .rotationEffect(chromeRotation)
        }
    }

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

    private var aspectRatioMenu: some View {
        Menu {
            ForEach(CameraAspectRatio.allCases, id: \.self) { aspectRatio in
                Button {
                    withAnimation(Self.compositionMorphAnimation(reduceMotion: reduceMotion)) {
                        model.selectCameraAspectRatio(aspectRatio)
                    }
                } label: {
                    Label(
                        aspectRatio.label,
                        systemImage: model.cameraAspectRatio == aspectRatio
                            ? "checkmark.circle.fill"
                            : "rectangle.dashed"
                    )
                }
                .accessibilityHint(aspectRatio.accessibilityHint)
            }
        } label: {
            Text(model.cameraAspectRatio.label)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PosterPalette.paperWhite)
                .padding(.horizontal, PosterSpacing.md)
                .frame(height: 48)
                .background(PosterEffects.cameraChromeFill)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(PosterEffects.cameraChromeStroke, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PosterPressStyle())
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("拍摄比例，当前为 \(model.cameraAspectRatio.label)")
        .accessibilityHint("选择全屏、16 比 9、3 比 4或1 比 1构图")
    }

    /// Aspect-frame morph: quick lift, soft settle — not a constant-speed wipe.
    fileprivate static func compositionMorphAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .timingCurve(0.14, 1.14, 0.22, 1, duration: 0.44)
    }

    /// Bottom: shutter and time selection are one morphing control.
    private var bottomChrome: some View {
        ShutterWaveTimeRail(
            value: model.selectedTime.normalized,
            onDetent: model.playTimeDetent,
            onChange: { normalized in
                model.updateTime(normalized: normalized)
            },
            onCapture: {
                fireShutterFlash()
                Task { await model.capture() }
            },
            chromeRotation: chromeRotation
        )
        .padding(.bottom, PosterSpacing.sm)
    }

    private var albumPickerButton: some View {
        PhotosPicker(
            selection: $albumPickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Image(systemName: "photo.on.rectangle")
                .font(.body.weight(.semibold))
                .foregroundStyle(PosterPalette.paperWhite)
                .frame(width: 48, height: 48)
                .background(PosterEffects.cameraChromeFill)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(PosterEffects.cameraChromeStroke, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PosterPressStyle())
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("从相册导入")
        .accessibilityHint("选择一张照片进入时间相机管线")
        .disabled(model.isPipelineBusy)
    }

    @ViewBuilder
    private var preview: some View {
        if reduceMotion {
            model.cameraPreview
        } else {
            model.cameraPreview
                .matchedGeometryEffect(id: "camera-photo", in: namespace)
        }
    }

    private func importAlbumItem(_ item: PhotosPickerItem) async {
        do {
            guard let raw = try await item.loadTransferable(type: AlbumImageData.self) else {
                model.lastErrorMessage = PhotoImportAdapter.ImportError.invalidImage.localizedDescription
                return
            }
            fireShutterFlash()
            await model.importPhoto(imageData: raw.data)
        } catch {
            model.lastErrorMessage = error.localizedDescription
        }
    }

    private func fireShutterFlash() {
        if reduceMotion {
            shutterFlash = 0.45
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                shutterFlash = 0
            }
            return
        }
        withAnimation(.linear(duration: PosterMotion.micro * 0.55)) {
            shutterFlash = 0.72
        }
        withAnimation(.linear(duration: PosterMotion.micro).delay(PosterMotion.micro * 0.55)) {
            shutterFlash = 0
        }
    }

    private func updateCaptureOrientation(_ orientation: UIDeviceOrientation) {
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

private struct CameraCompositionOverlay: View {
    let aspectRatio: CameraAspectRatio
    let showsGrid: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let cropFrame = compositionFrame(in: proxy.size)
            let captureViewport = captureViewport(in: proxy.size)

            ZStack {
                if let cropFrame {
                    let cornerRadius = compositionCornerRadius(for: cropFrame)

                    CameraFrostedCompositionMask(
                        cropFrame: cropFrame,
                        cornerRadius: cornerRadius
                    )
                    .transition(.opacity)

                    if showsGrid {
                        CameraCompositionGrid(
                            frame: cropFrame,
                            cornerRadius: cornerRadius
                        )
                        .transition(.opacity)
                    }
                } else if showsGrid {
                    CameraCompositionGrid(
                        frame: captureViewport,
                        cornerRadius: 0
                    )
                }
            }
            .animation(compositionAnimation, value: aspectRatio)
            .animation(compositionAnimation, value: showsGrid)
        }
    }

    private var compositionAnimation: Animation? {
        ViewfinderView.compositionMorphAnimation(reduceMotion: reduceMotion)
    }

    /// Shared middle band. Classic / square keep side gutters; chrome may float
    /// over frost at the bottom so we never carve a dead rectangular dock.
    private func captureViewport(in size: CGSize) -> CGRect {
        if aspectRatio == .fullScreen {
            return CGRect(origin: .zero, size: size)
        }
        let topInset = min(92, size.height * 0.12)
        let bottomInset = min(156, size.height * 0.19)
        let gutter = sideGutter(in: size)
        return CGRect(
            x: gutter,
            y: topInset,
            width: max(0, size.width - gutter * 2),
            height: max(0, size.height - topInset - bottomInset)
        )
    }

    /// Match the comfortable side air of 16:9 / 1:1 — classic must not kiss the edges.
    private func sideGutter(in size: CGSize) -> CGFloat {
        switch aspectRatio {
        case .fullScreen, .widescreen:
            return 0
        case .classic, .square:
            return max(12, min(20, size.width * 0.04))
        }
    }

    private func compositionFrame(in size: CGSize) -> CGRect? {
        guard let ratio = aspectRatio.targetAspectRatio(for: size) else { return nil }
        let viewport = captureViewport(in: size)
        guard viewport.width > 0, viewport.height > 0 else { return nil }

        let availableRatio = viewport.width / viewport.height
        let frameSize: CGSize
        if availableRatio > ratio {
            frameSize = CGSize(width: viewport.height * ratio, height: viewport.height)
        } else {
            frameSize = CGSize(width: viewport.width, height: viewport.width / ratio)
        }

        return CGRect(
            x: viewport.midX - frameSize.width / 2,
            y: viewport.midY - frameSize.height / 2,
            width: frameSize.width,
            height: frameSize.height
        )
    }

    private func compositionCornerRadius(for frame: CGRect) -> CGFloat {
        min(34, max(24, min(frame.width, frame.height) * 0.08))
    }
}

/// Uses the live preview as the source for the composition surround. iOS 26
/// gets native Liquid Glass; earlier targets receive the equivalent system
/// material. The mask is non-interactive and leaves the selected frame clear.
private struct CameraFrostedCompositionMask: View {
    let cropFrame: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        .regular.tint(PosterPalette.ink.opacity(0.06)),
                        in: .rect(cornerRadius: 0)
                    )
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .mask {
            ZStack {
                Color.white

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black)
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
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

        var body: some View {
            ViewfinderView(model: PreviewFixtures.model(phase: .viewfinder), namespace: namespace)
        }
    }
    return PreviewWrapper()
}

#Preview("Scrubbed time") {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            ViewfinderView(
                model: PreviewFixtures.model(phase: .viewfinder, time: 0.35),
                namespace: namespace
            )
        }
    }
    return PreviewWrapper()
}

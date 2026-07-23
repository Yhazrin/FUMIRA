import PhotosUI
import SwiftUI

struct ViewfinderView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsAreReady = false
    @State private var shutterFlash = 0.0
    @State private var albumPickerItem: PhotosPickerItem?

    private var timeChipLabel: String {
        let year = Calendar.current.component(.year, from: model.selectedTime.targetDate())
        if abs(model.selectedTime.offsetDays) < 0.5 {
            return "NOW · \(year)"
        }
        return "\(model.selectedTime.compactLabel) · \(year)"
    }

    var body: some View {
        ZStack {
            preview
                .ignoresSafeArea()

            if model.isCameraGridEnabled {
                CameraGridOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // Top / bottom scrims only — never a large white control card.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [PosterEffects.cameraTopScrim, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Color.clear, PosterEffects.cameraBottomScrim],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(.top, PosterSpacing.sm)
                    .allowsHitTesting(controlsAreReady)

                Spacer(minLength: 0)

                bottomChrome
                    .padding(.horizontal, PosterSpacing.md)
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
            await model.refreshCameraControls()
            try? await Task.sleep(for: PosterMotion.cameraInputGuard)
            guard !Task.isCancelled else { return }
            controlsAreReady = true
        }
        .onChange(of: albumPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importAlbumItem(newItem)
                albumPickerItem = nil
            }
        }
    }

    /// Top: flash / flip (when live) + status + minimal time chip — no slogan, no dead controls.
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
                }

                if !model.isUsingLiveCamera {
                    Text("模拟器")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PosterPalette.paperWhite.opacity(0.75))
                        .padding(.horizontal, PosterSpacing.sm)
                        .padding(.vertical, PosterSpacing.xs)
                        .background(PosterPalette.ink.opacity(0.35))
                        .clipShape(Capsule())
                        .accessibilityLabel("模拟器场景")
                }
            }

            Spacer(minLength: PosterSpacing.sm)

            Text(timeChipLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(PosterPalette.paperWhite)
                .padding(.horizontal, PosterSpacing.md)
                .padding(.vertical, PosterSpacing.sm)
                .background(PosterPalette.ink.opacity(0.4))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(PosterPalette.paperWhite.opacity(0.22), lineWidth: 1)
                }
                .accessibilityLabel("选中时间")
                .accessibilityValue(timeChipLabel)
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
    }

    /// Bottom: WaveTimeRail · album · shutter · grid.
    private var bottomChrome: some View {
        VStack(spacing: PosterSpacing.md) {
            WaveTimeRail(
                value: model.selectedTime.normalized,
                chrome: .immersive,
                onDetent: model.playTimeDetent
            ) { normalized in
                model.updateTime(normalized: normalized)
            }
            .padding(.horizontal, PosterSpacing.xs)

            HStack(alignment: .center, spacing: PosterSpacing.xl) {
                albumPickerButton

                ShutterButton {
                    fireShutterFlash()
                    Task { await model.capture() }
                }

                CameraChromeButton(
                    systemImage: model.isCameraGridEnabled ? "grid" : "grid.circle",
                    accessibilityLabelText: model.isCameraGridEnabled ? "关闭构图网格" : "打开构图网格",
                    accessibilityHintText: "切换取景辅助网格"
                ) {
                    model.toggleCameraGrid()
                }
            }
            .padding(.bottom, PosterSpacing.xs)
        }
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

private struct CameraGridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                for step in 1...2 {
                    let x = width * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    let y = height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(PosterPalette.paperWhite.opacity(0.35), lineWidth: 1)
        }
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

import AVFoundation
import SwiftUI

struct CameraPermissionView: View {
    let model: AppModel
    var onLaunchViewfinder: (() -> Void)?

    /// Hidden until we know the user still needs a prompt (first grant / denied).
    @State private var showPrompt = false

    var body: some View {
        Group {
            if showPrompt {
                PosterScreenContainer {
                    promptContent
                }
            } else {
                cameraEntryHold
            }
        }
        .task {
            await resolveEntry()
        }
        .preferredColorScheme(showPrompt ? .light : .dark)
    }

    /// Full-bleed blue bridge while permission / preview resolve. The viewfinder
    /// card itself slides down from RootView — never pre-place that silhouette.
    private var cameraEntryHold: some View {
        PosterPalette.actionBlue
            .ignoresSafeArea()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在进入取景器")
    }

    private var promptContent: some View {
        VStack(spacing: PosterSpacing.lg) {
            Spacer(minLength: PosterSpacing.xl)

            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .frame(width: 64, height: 64)
                .background(PosterPalette.actionBlue.opacity(0.14))
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text("拍下现在")
                .font(PosterTypography.screenTitle)
                .foregroundStyle(PosterPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.lastErrorMessage {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PosterPalette.errorCoral)
                    .multilineTextAlignment(.center)
            }

            PosterCapsuleButton(
                title: model.isUsingLiveCamera ? "打开相机" : "进入取景器",
                accessibilityHint: model.isUsingLiveCamera
                    ? "请求相机权限并进入实时取景"
                    : "继续进入取景器"
            ) {
                requestViewfinder()
            }
            .frame(maxWidth: 280)

            Spacer(minLength: PosterSpacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private func resolveEntry() async {
        guard canEnterWithoutPrompt else {
            showPrompt = true
            return
        }

        if let onLaunchViewfinder {
            onLaunchViewfinder()
            return
        }

        await model.grantCameraAccess()
        // Denied / failed — reveal the prompt so the user can recover.
        if model.phase == .cameraPermission {
            showPrompt = true
        }
    }

    /// Live camera skips only when the system already granted access.
    /// Mock / first-time live still shows the prompt so the user consents once.
    private var canEnterWithoutPrompt: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_AUTO_CAMERA_GRANT"] == "1" {
            return true
        }
        #endif
        guard model.isUsingLiveCamera else { return false }
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private func requestViewfinder() {
        if let onLaunchViewfinder {
            onLaunchViewfinder()
        } else {
            Task { await model.grantCameraAccess() }
        }
    }
}

#Preview {
    CameraPermissionView(model: PreviewFixtures.model(phase: .cameraPermission))
}

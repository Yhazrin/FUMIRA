import AVFoundation
import SwiftUI

struct CameraPermissionView: View {
    let model: AppModel

    /// Hidden until we know the user still needs a prompt (first grant / denied).
    @State private var showPrompt = false

    var body: some View {
        PosterScreenContainer {
            if showPrompt {
                promptContent
            } else {
                // Solid hold (not Color.clear) while auto-skipping to the viewfinder.
                PosterPalette.canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("正在进入取景器")
            }
        }
        .task {
            await resolveEntry()
        }
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

            Text(guidance)
                .font(.headline.weight(.semibold))
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
                Task { await model.grantCameraAccess() }
            }
            .frame(maxWidth: 280)

            Spacer(minLength: PosterSpacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private var guidance: String {
        model.isUsingLiveCamera
            ? "允许相机权限，开始拍摄"
            : "准备好后，开始取景"
    }

    private func resolveEntry() async {
        guard canEnterWithoutPrompt else {
            showPrompt = true
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
        guard model.isUsingLiveCamera else { return false }
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
}

#Preview {
    CameraPermissionView(model: PreviewFixtures.model(phase: .cameraPermission))
}

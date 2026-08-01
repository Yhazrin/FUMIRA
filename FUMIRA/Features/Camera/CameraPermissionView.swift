import AVFoundation
import SwiftUI

struct CameraPermissionView: View {
    let model: AppModel
    var onLaunchViewfinder: (() -> Void)?

    @State private var showPrompt = false

    var body: some View {
        Group {
            if showPrompt {
                ClayPanel(
                    base: ClayPalette.warmWhite,
                    rim: ClayPalette.warmWhiteRim,
                    cornerRadius: ClayShape.panel
                ) {
                    promptContent
                }
                .padding(.horizontal, ClaySpacing.screenEdgeMargin)
            } else {
                cameraEntryHold
            }
        }
        .task {
            await resolveEntry()
        }
        .preferredColorScheme(showPrompt ? .light : .dark)
    }

    private var cameraEntryHold: some View {
        ClayPalette.orange
            .ignoresSafeArea()
            .overlay {
                ClayNoiseTexture(opacity: 0.10)
                    .ignoresSafeArea()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在进入取景器")
    }

    private var promptContent: some View {
        VStack(spacing: ClaySpacing.xxl) {
            Spacer(minLength: ClaySpacing.xxxl)

            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(ClayPalette.orange)
                .frame(width: 64, height: 64)
                .background {
                    Circle()
                        .fill(ClayPalette.orange.opacity(0.14))
                }
                .accessibilityHidden(true)

            Text("拍下现在")
                .font(ClayTypography.displaySmall)
                .foregroundStyle(ClayPalette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.lastErrorMessage {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ClayPalette.error)
                    .multilineTextAlignment(.center)
            }

            Button {
                requestViewfinder()
            } label: {
                Text(model.isUsingLiveCamera ? "打开相机" : "进入取景器")
                    .font(ClayTypography.bodyBold)
                    .foregroundStyle(ClayPalette.charcoal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .clayButtonStyle(
                base: ClayPalette.orange,
                rim: ClayPalette.orangeRim
            )
            .frame(maxWidth: 280)

            Spacer(minLength: ClaySpacing.xxxl)
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
        if model.phase == .cameraPermission {
            showPrompt = true
        }
    }

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

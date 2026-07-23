import SwiftUI

struct CameraPermissionView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.xl) {
                Spacer()

                PosterKeywordHero(moment: .ready, fontSize: 40)

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(PosterPalette.pine)
                    .padding(.vertical, PosterSpacing.xl)
                    .accessibilityHidden(true)

                Text(permissionExplanation)
                    .font(.body)
                    .foregroundStyle(PosterPalette.ink)
                    .multilineTextAlignment(.leading)

                if let message = model.lastErrorMessage {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(PosterPalette.errorCoral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                PosterCapsuleButton(
                    title: "允许并进入取景器",
                    accessibilityHint: model.isUsingLiveCamera
                        ? "打开系统相机权限并进入实时取景"
                        : "进入模拟器取景场景"
                ) {
                    Task { await model.grantCameraAccess() }
                }
            }
        }
    }

    private var permissionExplanation: String {
        if model.isUsingLiveCamera {
            "首次使用会弹出系统相机权限。照片只在你按下快门后交给 FUMIRA 的识图与时间故事流程。"
        } else {
            "当前是模拟器环境，将使用可交互场景代替硬件相机；在实体 iPhone 上会自动切换为实时取景。"
        }
    }
}

#Preview {
    CameraPermissionView(model: PreviewFixtures.model(phase: .cameraPermission))
}

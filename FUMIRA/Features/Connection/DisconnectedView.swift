import SwiftUI

struct DisconnectedView: View {
    let model: AppModel
    var message: String?

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.xl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(PosterPalette.errorCoral.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(PosterPalette.errorCoral)
                }
                .accessibilityHidden(true)

                PosterTitleView(
                    segments: ["连接", "已断开"],
                    color: PosterPalette.errorCoral,
                    fontSize: 38
                )

                Text(message ?? model.lastErrorMessage ?? "FutureCam 连接中断，可以重新连接或改用手机体验。")
                    .font(.body)
                    .foregroundStyle(PosterPalette.ink)
                    .multilineTextAlignment(.leading)

                Spacer()

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: "重新连接",
                        accessibilityHint: "返回连接页面"
                    ) {
                        model.recoverConnection()
                    }

                    PosterCapsuleButton(
                        title: "仅用手机体验",
                        style: .secondary
                    ) {
                        model.beginPhoneOnlyPath()
                    }
                }
            }
        }
    }
}

#Preview {
    DisconnectedView(model: PreviewFixtures.model(phase: .disconnected))
}

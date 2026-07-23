import SwiftUI

struct ConnectionView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.xl) {
                Spacer(minLength: PosterSpacing.lg)

                PosterTitleView(
                    segments: ["给", "时间", "一张", "照片"],
                    color: PosterPalette.timeBlue,
                    fontSize: 44
                )

                PosterScriptSubtitle(text: "Future Camera")

                Spacer()

                FutureCamBody()
                    .padding(.vertical, PosterSpacing.lg)

                Spacer()

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: "连接 FutureCam",
                        accessibilityHint: "通过蓝牙连接实体时间旋钮"
                    ) {
                        model.beginHardwarePath()
                    }

                    PosterCapsuleButton(
                        title: "仅用手机体验",
                        style: .secondary,
                        accessibilityHint: "跳过硬件，直接进入手机拍摄流程"
                    ) {
                        model.beginPhoneOnlyPath()
                    }
                }
            }
        }
    }
}

#Preview {
    ConnectionView(model: PreviewFixtures.model(phase: .connection))
}

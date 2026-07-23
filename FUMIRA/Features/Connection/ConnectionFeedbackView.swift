import SwiftUI

struct ConnectionFeedbackView: View {
    let model: AppModel
    let snapshot: HardwareSnapshot

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.xl) {
                Spacer()

                PosterTitleView(
                    segments: ["已连接"],
                    color: PosterPalette.parkGreen,
                    fontSize: 44
                )

                PosterScriptSubtitle(text: snapshot.name)

                HStack(spacing: PosterSpacing.md) {
                    StatusPill(icon: "checkmark.circle.fill", label: "已连接", isActive: true)
                    StatusPill(icon: "battery.75", label: "\(snapshot.batteryLevel)%")
                }
                .padding(.top, PosterSpacing.lg)

                FutureCamBody()
                    .padding(.vertical, PosterSpacing.xl)

                Spacer()

                PosterCapsuleButton(
                    title: "继续",
                    accessibilityHint: "进入相机权限步骤"
                ) {
                    model.continueFromConnection()
                }
            }
        }
    }
}

#Preview {
    ConnectionFeedbackView(
        model: PreviewFixtures.model(phase: .connected),
        snapshot: HardwareSnapshot(name: "FutureCam_01", batteryLevel: 86)
    )
}

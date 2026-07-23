import SwiftUI

struct BluetoothPermissionView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.xl) {
                Spacer()

                PosterTitleView(
                    segments: ["连上", "FutureCam"],
                    color: PosterPalette.sky,
                    fontSize: 40
                )

                PosterScriptSubtitle(text: "Bluetooth")

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(PosterPalette.pine)
                    .padding(.vertical, PosterSpacing.xl)
                    .accessibilityHidden(true)

                Text("需要蓝牙权限来发现实体快门与时间旋钮。这是应用内说明，不会弹出系统对话框。")
                    .font(.body)
                    .foregroundStyle(PosterPalette.ink)
                    .multilineTextAlignment(.leading)

                Spacer()

                PosterCapsuleButton(
                    title: "允许并连接",
                    accessibilityHint: "模拟授权后开始连接硬件"
                ) {
                    Task { await model.grantBluetoothAndConnect() }
                }
            }
        }
    }
}

#Preview {
    BluetoothPermissionView(model: PreviewFixtures.model(phase: .bluetoothPermission))
}

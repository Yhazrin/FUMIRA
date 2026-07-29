import SwiftUI

struct BluetoothPermissionView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.lg) {
                Spacer(minLength: PosterSpacing.xl)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(PosterPalette.skyDeep)
                    .frame(width: 64, height: 64)
                    .background(PosterPalette.sky.opacity(0.18))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                Text("连接 FutureCam")
                    .font(PosterTypography.screenTitle)
                    .foregroundStyle(PosterPalette.ink)
                    .multilineTextAlignment(.center)

                PosterCapsuleButton(
                    title: "继续",
                    accessibilityHint: "授权后开始连接硬件"
                ) {
                    Task { await model.grantBluetoothAndConnect() }
                }
                .frame(maxWidth: 280)

                Spacer(minLength: PosterSpacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    BluetoothPermissionView(model: PreviewFixtures.model(phase: .bluetoothPermission))
}

import SwiftUI

struct BluetoothPermissionView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: ClaySpacing.xxl) {
                Spacer(minLength: ClaySpacing.xxxl)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(ClayPalette.orange)
                    .frame(width: 64, height: 64)
                    .background {
                        Circle()
                            .fill(ClayPalette.orange.opacity(0.18))
                    }
                    .accessibilityHidden(true)

                Text("连接 FutureCam")
                    .font(ClayTypography.displaySmall)
                    .foregroundStyle(ClayPalette.textOnDark)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await model.grantBluetoothAndConnect() }
                } label: {
                    Text("继续")
                        .font(ClayTypography.bodyBold)
                        .foregroundStyle(ClayPalette.charcoal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .clayButtonStyle()
                .frame(maxWidth: 280)

                Spacer(minLength: ClaySpacing.xxxl)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    BluetoothPermissionView(model: PreviewFixtures.model(phase: .bluetoothPermission))
}

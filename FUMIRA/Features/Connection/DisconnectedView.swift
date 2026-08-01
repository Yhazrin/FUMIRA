import SwiftUI

struct DisconnectedView: View {
    let model: AppModel
    var message: String?

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: ClaySpacing.xxxl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(ClayPalette.error.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(ClayPalette.error)
                }
                .accessibilityHidden(true)

                Text("连接已断开")
                    .font(ClayTypography.displaySmall)
                    .foregroundStyle(ClayPalette.textOnDark)

                if let message {
                    Text(message)
                        .font(ClayTypography.body)
                        .foregroundStyle(ClayPalette.textOnDark.opacity(0.72))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                VStack(spacing: ClaySpacing.lg) {
                    Button {
                        model.recoverConnection()
                    } label: {
                        Text("重新连接")
                            .font(ClayTypography.bodyBold)
                            .foregroundStyle(ClayPalette.charcoal)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .clayButtonStyle()

                    Button {
                        model.beginPhoneOnlyPath()
                    } label: {
                        Text("仅用手机体验")
                            .font(ClayTypography.bodyBold)
                            .foregroundStyle(ClayPalette.textOnDark)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        RoundedRectangle(cornerRadius: ClayShape.button, style: .continuous)
                            .stroke(ClayPalette.warmWhite.opacity(0.24), lineWidth: 1.5)
                    }
                }
            }
        }
    }
}

#Preview {
    DisconnectedView(model: PreviewFixtures.model(phase: .disconnected))
}

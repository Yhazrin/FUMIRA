import SwiftUI

struct ConnectionFeedbackView: View {
    let model: AppModel
    let snapshot: HardwareSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PosterPalette.canvas.ignoresSafeArea()

            LinearGradient(
                colors: [
                    PosterPalette.sky.opacity(0.42),
                    PosterPalette.canvas,
                    PosterPalette.grassLight.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: PosterSpacing.xl) {
                Spacer(minLength: PosterSpacing.lg)

                PosterKeywordHero(moment: .connecting, fontSize: 42)
                    .padding(.horizontal, PosterSpacing.lg)

                HStack(spacing: PosterSpacing.md) {
                    StatusPill(icon: "checkmark.circle.fill", label: "已连接", isActive: true)
                    StatusPill(icon: "battery.75", label: "\(snapshot.batteryLevel)%")
                }

                Text(snapshot.name)
                    .font(PosterTypography.script(24))
                    .foregroundStyle(PosterPalette.mutedInk)

                TemporalParkScene(time: .now, cornerRadius: PosterRadius.card)
                    .frame(height: 180)
                    .padding(.horizontal, PosterSpacing.xl)
                    .shadow(color: PosterEffects.floating, radius: 14, y: 8)
                    .accessibilityHidden(true)

                Spacer()

                PosterCapsuleButton(
                    title: "继续",
                    accessibilityHint: "进入相机权限步骤"
                ) {
                    model.continueFromConnection()
                }
                .padding(.horizontal, PosterSpacing.lg)
                .padding(.bottom, PosterSpacing.xl)
            }
        }
        .animation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : .spring(response: PosterMotion.poster, dampingFraction: 0.86),
            value: snapshot.batteryLevel
        )
    }
}

#Preview {
    ConnectionFeedbackView(
        model: PreviewFixtures.model(phase: .connected),
        snapshot: HardwareSnapshot(name: "FutureCam_01", batteryLevel: 86)
    )
}

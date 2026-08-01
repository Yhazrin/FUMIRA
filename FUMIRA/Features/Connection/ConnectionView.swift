import SwiftUI

struct ConnectionView: View {
    let model: AppModel
    var entryProgress: CGFloat = 0
    let onLaunchCamera: () -> Void

    init(
        model: AppModel,
        entryProgress: CGFloat = 0,
        onLaunchCamera: @escaping () -> Void = {}
    ) {
        self.model = model
        self.entryProgress = entryProgress
        self.onLaunchCamera = onLaunchCamera
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Clay 背景 — 深炭 + 颗粒
                ClayAppBackground()
                    .ignoresSafeArea()

                FUMIRAWordmark()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, ClaySpacing.xxl)
                    .padding(
                        .top,
                        proxy.safeAreaInsets.top + ClaySpacing.xxxl + 28
                    )
                    .opacity(1 - FUMIRASpatialMotion.map(entryProgress, from: 0.18...0.62, to: 0...1))
                    .scaleEffect(1 - FUMIRASpatialMotion.map(entryProgress, from: 0...0.62, to: 0...0.035), anchor: .topLeading)

                if entryProgress <= 0.001 {
                    CameraLaunchClayButton(action: onLaunchCamera)
                        .position(
                            x: proxy.size.width * 0.5,
                            y: proxy.size.height * 0.46
                        )
                        .transition(.identity)
                }
            }
        }
    }
}

private struct FUMIRAWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FUMIRA")
                .font(ClayTypography.displayLarge)
                .foregroundStyle(ClayPalette.textOnDark)
                .tracking(1.2)

            HStack(spacing: ClaySpacing.sm) {
                Capsule()
                    .fill(ClayPalette.orange)
                    .frame(width: 36, height: 4)

                Text("TIME CAMERA")
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(0.55))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FUMIRA 时间相机")
    }
}

private struct CameraLaunchClayButton: View {
    let action: () -> Void

    var body: some View {
        ZStack {
            ClayMoldedControl(
                base: ClayPalette.warmWhite,
                rim: ClayPalette.warmWhiteRim,
                foreground: .clear,
                cornerRadius: ClayShape.pill,
                depth: 5,
                isPressed: false
            ) {
                Color.clear
                    .frame(width: 118, height: 118)
            }
            .shadow(
                color: ClayShadow.card.color,
                radius: ClayShadow.card.radius,
                x: ClayShadow.card.x,
                y: ClayShadow.card.y
            )

            Button(action: action) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 29, weight: .bold))
                    .frame(width: 82, height: 82)
            }
            .clayButtonStyle(
                base: ClayPalette.orange,
                rim: ClayPalette.orangeDepth,
                foreground: ClayPalette.charcoal,
                cornerRadius: ClayShape.pill,
                depth: 5
            )
            .contentShape(Circle())
        }
        .accessibilityLabel("进入时间相机")
        .accessibilityHint("打开相机，拍下一张给时间的照片")
    }
}

#Preview("Invite") {
    ConnectionView(
        model: PreviewFixtures.model(phase: .connection)
    )
}

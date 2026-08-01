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
        Button(action: action) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(ClayPalette.charcoal)
                .frame(width: 88, height: 88)
                .background {
                    ZStack {
                        Circle()
                            .fill(ClayPalette.orangeRim)
                            .offset(y: ClayShape.rimOffset)

                        Circle()
                            .fill(ClayPalette.orange)
                            .overlay {
                                LinearGradient(
                                    stops: ClayShadow.highlightStops,
                                    startPoint: ClayShadow.highlightStart,
                                    endPoint: ClayShadow.highlightEnd
                                )
                                .clipShape(Circle())
                            }
                            .overlay {
                                ClayNoiseTexture(opacity: 0.14)
                                    .clipShape(Circle())
                            }
                            .overlay {
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: ClayShadow.edgeStrokeColors,
                                            startPoint: ClayShadow.edgeStrokeStart,
                                            endPoint: ClayShadow.edgeStrokeEnd
                                        ),
                                        lineWidth: 2
                                    )
                            }
                    }
                }
                .shadow(
                    color: ClayShadow.rest.color,
                    radius: ClayShadow.rest.radius,
                    x: ClayShadow.rest.x,
                    y: ClayShadow.rest.y
                )
                .contentShape(Circle())
        }
        .buttonStyle(ClayPressButtonStyle())
        .accessibilityLabel("进入时间相机")
        .accessibilityHint("打开相机，拍下一张给时间的照片")
    }
}

/// 按压反馈按钮样式 — 下沉 + 阴影压缩
private struct ClayPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? ClayMotion.pressScale : 1)
            .offset(y: configuration.isPressed ? ClayMotion.pressOffsetY : 0)
            .shadow(
                color: configuration.isPressed
                    ? ClayShadow.pressed.color
                    : ClayShadow.rest.color,
                radius: configuration.isPressed
                    ? ClayShadow.pressed.radius
                    : ClayShadow.rest.radius,
                x: 0,
                y: configuration.isPressed
                    ? ClayShadow.pressed.y
                    : ClayShadow.rest.y
            )
            .animation(ClayMotion.buttonSpring, value: configuration.isPressed)
    }
}

#Preview("Invite") {
    ConnectionView(
        model: PreviewFixtures.model(phase: .connection)
    )
}

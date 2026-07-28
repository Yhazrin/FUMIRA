import SwiftUI

struct ConnectionView: View {
    let model: AppModel
    let onLaunchCamera: () -> Void

    init(
        model: AppModel,
        onLaunchCamera: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onLaunchCamera = onLaunchCamera
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("ConnectionBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .ignoresSafeArea()

                FUMIRAWordmark()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(
                        .top,
                        proxy.safeAreaInsets.top + PosterSpacing.xl + 12
                    )

                CameraLaunchIconButton(action: onLaunchCamera)
                    .position(
                        x: proxy.size.width * 0.5,
                        y: proxy.size.height * 0.46
                    )
            }
        }
    }
}

private struct FUMIRAWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FUMIRA")
                .font(PosterTypography.script(68))
                .foregroundStyle(PosterPalette.actionBlueDeep)

            HStack(spacing: PosterSpacing.sm) {
                Capsule()
                    .fill(PosterPalette.toyRed)
                    .frame(width: 32, height: 4)

                Text("TIME CAMERA")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(PosterPalette.actionBlueDeep.opacity(0.76))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FUMIRA 时间相机")
    }
}

private struct CameraLaunchIconButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(PosterPalette.paperWhite)
                .frame(width: 88, height: 88)
                .background(PosterPalette.actionBlueDeep)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel("进入时间相机")
        .accessibilityHint("打开相机，拍下一张给时间的照片")
    }
}

#Preview("Invite") {
    ConnectionView(
        model: PreviewFixtures.model(phase: .connection)
    )
}

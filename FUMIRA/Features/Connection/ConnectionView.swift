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
                        proxy.safeAreaInsets.top + PosterSpacing.xl + 28
                    )
                    .opacity(1 - FUMIRASpatialMotion.map(entryProgress, from: 0.18...0.62, to: 0...1))
                    .scaleEffect(1 - FUMIRASpatialMotion.map(entryProgress, from: 0...0.62, to: 0...0.035), anchor: .topLeading)

                // RootView promotes the touched control into CameraEntryPortal.
                // Remove this source immediately once that persistent copy is
                // active so two identical apertures never cross-fade and read
                // as a flash or duplicated redraw.
                if entryProgress <= 0.001 {
                    CameraLaunchIconButton(action: onLaunchCamera)
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
                .font(PosterTypography.wordmark)
                .foregroundStyle(PosterPalette.actionBlue)
                .tracking(1.2)

            HStack(spacing: PosterSpacing.sm) {
                Capsule()
                    .fill(PosterPalette.toyRed)
                    .frame(width: 36, height: 4)

                Text("TIME CAMERA")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(PosterPalette.actionBlue.opacity(0.72))
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
                .background(PosterPalette.actionBlue)
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

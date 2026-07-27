import SwiftUI

/// Shutter dwell stage — chrome only. The persistent hero hosts the photo body.
struct ShutterFeedbackView: View {
    let model: AppModel
    var namespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            let layout = CameraCompositionGeometry.layout(
                aspectRatio: model.cameraAspectRatio,
                in: proxy.size
            )

            // Same local place+measure path as ViewfinderView so the hero does
            // not jump when the phase flips to shuttered.
            HeroPhotoSlot(
                owner: .shuttered,
                aspectRatio: layout.heroFrame.width / max(layout.heroFrame.height, 1),
                cornerRadius: layout.cornerRadius,
                fixedFrame: layout.heroFrame
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityLabel("快门反馈")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            ShutterFeedbackView(model: PreviewFixtures.model(phase: .shuttered), namespace: namespace)
        }
    }
    return PreviewWrapper()
}

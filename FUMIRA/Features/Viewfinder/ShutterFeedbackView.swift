import SwiftUI

struct ShutterFeedbackView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashOpacity = 0.0

    var body: some View {
        ZStack {
            PosterPalette.canvas.ignoresSafeArea()

            CapturedPhotoView(photo: model.capturedPhoto, cornerRadius: 0)
            .modifier(CapturedPhotoGeometry(
                namespace: namespace,
                reduceMotion: reduceMotion
            ))
            .opacity(reduceMotion ? 0.85 : 0.7)
            .ignoresSafeArea()

            PosterPalette.canvas
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else {
                flashOpacity = 0.6
                return
            }
            withAnimation(.linear(duration: PosterMotion.micro)) {
                flashOpacity = 0.85
            }
            withAnimation(.linear(duration: PosterMotion.micro).delay(PosterMotion.micro)) {
                flashOpacity = 0
            }
        }
        .accessibilityLabel("快门反馈")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct CapturedPhotoGeometry: ViewModifier {
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.matchedGeometryEffect(id: "camera-photo", in: namespace)
        }
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

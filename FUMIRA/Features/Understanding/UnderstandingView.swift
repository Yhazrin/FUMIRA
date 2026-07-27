import SwiftUI

struct UnderstandingView: View {
    let model: AppModel
    var namespace: Namespace.ID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chromeVisible = false

    private var photoAspectRatio: CGFloat {
        CGFloat(
            model.generatedPhoto?.displayAspectRatio
                ?? model.capturedPhoto?.displayAspectRatio
                ?? 3.0 / 4.0
        )
    }

    var body: some View {
        ZStack {
            // Backdrop owned by RootView — keep page chrome transparent to it.
            Color.clear

            VStack(alignment: .leading, spacing: 0) {
                Label("目标 \(model.generationTargetTime.compactLabel)", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PosterPalette.actionBlueDeep)

                Text("它已经到了，先不揭晓")
                    .font(PosterTypography.display(32))
                    .foregroundStyle(PosterPalette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PosterSpacing.xs)
                .opacity(chromeVisible ? 1 : 0)
                .offset(y: chromeVisible ? 0 : -8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, PosterSpacing.lg)
            .padding(.top, PosterSpacing.xl + PosterSpacing.md)

            // RootView's persistent hero lands just below the screen center,
            // so the captured frame travels downward as it becomes paper.
            GeometryReader { proxy in
                let rootBounds = proxy.frame(in: .named(HeroCoordinateSpace.name))
                let localFrame = HeroPhotoMetrics.understandingFrame(
                    aspectRatio: photoAspectRatio,
                    in: proxy.size
                )
                HeroPhotoFrameReporter(
                    owner: .understanding,
                    frame: localFrame.offsetBy(
                        dx: rootBounds.minX,
                        dy: rootBounds.minY
                    ),
                    cornerRadius: PosterRadius.photoPaper
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                    Text(model.pipelineStatusText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PosterPalette.ink)

                    ProgressView(value: model.understandingProgress)
                        .tint(PosterPalette.actionBlue)
                        .scaleEffect(x: 1, y: 2, anchor: .center)

                    Text("\(Int(model.understandingProgress * 100))% · 正在读取生成照片中的可见细节，完成前保持封存")
                        .font(.footnote)
                        .foregroundStyle(PosterPalette.mutedInk)
                }
                .opacity(chromeVisible ? 1 : 0)
                .offset(y: chromeVisible ? 0 : 10)

            }
            .padding(.horizontal, PosterSpacing.lg)
            .padding(.bottom, PosterSpacing.xl + PosterSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                chromeVisible = true
            } else {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: PosterMotion.phaseTransition)) {
                    chromeVisible = true
                }
            }
        }
    }
}

#Preview {
    UnderstandingView(
        model: PreviewFixtures.model(phase: .understanding, progress: 0.56)
    )
}

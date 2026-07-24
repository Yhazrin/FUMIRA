import SwiftUI

struct UnderstandingView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanPosition = -0.8

    private var photoAspectRatio: CGFloat {
        CGFloat(model.capturedPhoto?.displayAspectRatio ?? 3.0 / 4.0)
    }

    var body: some View {
        PosterScreenContainer(background: PosterPalette.skyDeep) {
            VStack(alignment: .leading, spacing: PosterSpacing.lg) {
                PosterTitleView(
                    segments: ["先", "读懂", "这一刻"],
                    color: PosterPalette.paperWhite,
                    fontSize: 36
                )

                PhotoAspectContainer(
                    aspectRatio: photoAspectRatio,
                    maximumHeight: 400
                ) {
                    ZStack {
                        CapturedPhotoView(photo: model.capturedPhoto)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        GeometryReader { proxy in
                            Rectangle()
                                .fill(PosterPalette.leafGreen)
                                .frame(height: 4)
                                .shadow(color: PosterPalette.leafGreen, radius: 12)
                                .offset(y: proxy.size.height * scanPosition)
                        }
                        .opacity(reduceMotion ? 0 : 0.9)

                        VStack {
                            Spacer()
                            HStack {
                                Label(
                                    model.modelOption(for: .understanding)?.displayName ?? "图片理解",
                                    systemImage: "viewfinder"
                                )
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PosterPalette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(PosterPalette.leafGreen)
                                .clipShape(Capsule())
                                Spacer()
                            }
                            .padding(PosterSpacing.md)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card))
                }

                VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                    Text(model.pipelineStatusText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PosterPalette.paperWhite)

                    ProgressView(value: model.understandingProgress)
                        .tint(PosterPalette.leafGreen)
                        .scaleEffect(x: 1, y: 2, anchor: .center)

                    Text("\(Int(model.understandingProgress * 100))% · 正在识别主体、空间与变化线索")
                        .font(.footnote)
                        .foregroundStyle(PosterPalette.paperWhite.opacity(0.72))
                }

                Spacer(minLength: PosterSpacing.sm)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: true)) {
                scanPosition = 0.8
            }
        }
    }
}

#Preview {
    UnderstandingView(
        model: PreviewFixtures.model(phase: .understanding, progress: 0.56)
    )
}

import SwiftUI

struct StoryWritingView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeYear = -100
    @State private var chromeVisible = false

    private let years = [-100, -30, -10, 0, 10, 30, 100]

    private var photoAspectRatio: CGFloat {
        CGFloat(
            model.generatedPhoto?.displayAspectRatio
                ?? model.capturedPhoto?.displayAspectRatio
                ?? 3.0 / 4.0
        )
    }

    /// Keep the story-seed thumbnail on the capture aspect (≈112pt tall, ≤88pt wide).
    private var storyThumbnailWidth: CGFloat {
        let ratio = max(photoAspectRatio, 0.01)
        let maxHeight: CGFloat = 112
        let maxWidth: CGFloat = 88
        return min(maxWidth, max(44, maxHeight * ratio))
    }

    var body: some View {
        PosterScreenContainer(background: Color.clear) {
            VStack(alignment: .leading, spacing: PosterSpacing.xl) {
                HStack(alignment: .top, spacing: PosterSpacing.md) {
                    VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                        Label("照片理解完成", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PosterPalette.actionBlueDeep)

                        Text("故事正在成形")
                            .font(PosterTypography.display(32))
                            .foregroundStyle(PosterPalette.ink)
                            .lineLimit(2)
                    }
                    .opacity(chromeVisible ? 1 : 0)
                    .offset(y: chromeVisible ? 0 : -6)

                    Spacer(minLength: 0)

                    // Thumbnail slot keeps the persistent hero alive through story writing.
                    // Width follows capture aspect — never force a square 88×88 box.
                    HeroPhotoSlot(
                        owner: .storyWriting,
                        aspectRatio: photoAspectRatio,
                        maximumHeight: 112,
                        cornerRadius: PosterRadius.photoPaper
                    )
                    .frame(width: storyThumbnailWidth)
                    .opacity(chromeVisible ? 1 : 0)
                }

                Text("目标画面的细节已经成为故事依据；照片与完整描述会在最后一起揭晓。")
                    .font(.body)
                    .foregroundStyle(PosterPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(chromeVisible ? 1 : 0)

                HStack(spacing: 5) {
                    ForEach(years, id: \.self) { year in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(year == activeYear ? PosterPalette.actionBlue : PosterPalette.actionBlue.opacity(0.18))
                                .frame(width: year == activeYear ? 20 : 10, height: year == activeYear ? 20 : 10)
                            Text(year == 0 ? "NOW" : String(format: "%+d", year))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(year == activeYear ? PosterPalette.actionBlueDeep : PosterPalette.mutedInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, PosterSpacing.lg)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(PosterPalette.actionBlue.opacity(0.18))
                        .frame(height: 2)
                        .offset(y: 9)
                }
                .opacity(chromeVisible ? 1 : 0)

                VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                    Text(model.pipelineStatusText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(PosterPalette.ink)
                    ProgressView(value: model.storyProgress)
                        .tint(PosterPalette.actionBlue)
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                    Text("故事模型正在围绕已经生成的目标画面，连接过去、现在与未来。")
                        .font(.footnote)
                        .foregroundStyle(PosterPalette.mutedInk)
                }
                .opacity(chromeVisible ? 1 : 0)

                Spacer(minLength: PosterSpacing.lg)
            }
        }
        .onAppear {
            if reduceMotion {
                chromeVisible = true
            } else {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: PosterMotion.phaseTransition)) {
                    chromeVisible = true
                }
            }
        }
        .task {
            guard !reduceMotion else {
                activeYear = 0
                return
            }
            for year in years {
                guard !Task.isCancelled else { return }
                activeYear = year
                try? await Task.sleep(for: .milliseconds(160))
            }
        }
    }
}

#Preview {
    StoryWritingView(
        model: PreviewFixtures.model(phase: .storyWriting, progress: 0.58)
    )
}

import SwiftUI

struct GenerationView: View {
    let model: AppModel
    var namespace: Namespace.ID

    private var yearText: String {
        let years = model.selectedTime.offsetYears
        if abs(years) < 0.5 { return "NOW" }
        return String(format: "%+.0f", years)
    }

    var body: some View {
        PosterScreenContainer(background: PosterPalette.pine) {
            VStack(spacing: PosterSpacing.lg) {
                PosterKeywordHero(moment: .growing, fontSize: 36, surface: .dark)

                Text(yearText)
                    .font(PosterTypography.display(72))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(PosterPalette.moss)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: 120)

                ZStack {
                    CapturedPhotoView(photo: model.capturedPhoto)
                        .frame(height: 190)
                        .opacity(1 - model.generationProgress * 0.45)

                    TemporalParkScene(
                        time: model.selectedTime,
                        namespace: namespace
                    )
                    .frame(height: 190)
                    .opacity(0.2 + model.generationProgress * 0.8)
                }
                .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.currentStoryBeat?.title ?? "时间正在改写画面")
                        .font(.headline)
                        .foregroundStyle(PosterPalette.paperWhite)
                    Text(model.currentNarrative)
                        .font(.footnote)
                        .foregroundStyle(PosterPalette.paperWhite.opacity(0.76))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: PosterSpacing.md) {
                    GenerationProgressRow(
                        title: "锁定原图主体",
                        progress: min(model.generationProgress * 1.4, 1),
                        isComplete: model.generationProgress > 0.25
                    )
                    GenerationProgressRow(
                        title: "注入时间故事",
                        progress: max(0, min((model.generationProgress - 0.2) * 1.5, 1)),
                        isComplete: model.generationProgress > 0.55
                    )
                    GenerationProgressRow(
                        title: "生成同一地点的变迁图",
                        progress: max(0, min((model.generationProgress - 0.5) * 2, 1)),
                        isComplete: model.generationProgress >= 1
                    )
                }

                Spacer(minLength: PosterSpacing.sm)

                HStack(spacing: PosterSpacing.md) {
                    Button("返回故事") {
                        model.activeSessionID = nil
                        model.phase = .storyReady
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .frame(minHeight: 44)
                    .accessibilityLabel("返回故事")
                    .accessibilityHint("停止当前生成并返回故事确认页")

                    Spacer()

                    Button("模拟超时") {
                        model.presentFailureForPreview()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PosterPalette.paperWhite.opacity(0.7))
                    .frame(minHeight: 44)
                    .accessibilityLabel("模拟超时")
                    .accessibilityHint("预览生成失败界面")
                }
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            GenerationView(
                model: PreviewFixtures.model(phase: .generating, progress: 0.45),
                namespace: namespace
            )
        }
    }
    return PreviewWrapper()
}

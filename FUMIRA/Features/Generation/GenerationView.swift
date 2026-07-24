import SwiftUI

struct GenerationView: View {
    let model: AppModel
    var namespace: Namespace.ID

    private var photoAspectRatio: CGFloat {
        CGFloat(model.capturedPhoto?.displayAspectRatio ?? 3.0 / 4.0)
    }

    private var yearText: String {
        let years = model.generationTargetTime.offsetYears
        if abs(years) < 0.5 { return "NOW" }
        return String(format: "%+.0f", years)
    }

    var body: some View {
        PosterScreenContainer(background: PosterPalette.skyDeep) {
            VStack(spacing: PosterSpacing.lg) {
                PosterKeywordHero(moment: .growing, fontSize: 36, surface: .dark)

                Text(yearText)
                    .font(PosterTypography.display(72))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(PosterPalette.leafGreen)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: 120)

                PhotoAspectContainer(
                    aspectRatio: photoAspectRatio,
                    maximumHeight: 260
                ) {
                    ZStack {
                        CapturedPhotoView(photo: model.capturedPhoto)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(1 - model.generationProgress * 0.45)

                        TemporalParkScene(
                            time: model.selectedTime,
                            namespace: namespace
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(0.2 + model.generationProgress * 0.8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.pipelineStatusText.isEmpty
                         ? (model.currentStoryBeat?.title ?? "时间正在生长")
                         : model.pipelineStatusText)
                        .font(.headline)
                        .foregroundStyle(PosterPalette.paperWhite)
                        .accessibilityLabel(model.pipelineStatusText.isEmpty
                            ? "时间正在生长"
                            : model.pipelineStatusText)
                    Text(model.currentNarrative)
                        .font(.footnote)
                        .foregroundStyle(PosterPalette.paperWhite.opacity(0.76))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: PosterSpacing.md) {
                    GenerationProgressRow(
                        title: "收集此刻的种子",
                        progress: seedProgress,
                        isComplete: model.generationProgress >= 0.35
                    )
                    GenerationProgressRow(
                        title: "时间正在生长",
                        progress: growthProgress,
                        isComplete: model.generationProgress >= 0.9
                    )
                    GenerationProgressRow(
                        title: "收成这一帧",
                        progress: harvestProgress,
                        isComplete: model.generationProgress >= 1
                    )
                }

                Spacer(minLength: PosterSpacing.sm)

                HStack(spacing: PosterSpacing.md) {
                    Button("取消生成") {
                        model.cancelGeneration()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .frame(minHeight: 44)
                    .accessibilityLabel("取消生成")
                    .accessibilityHint("停止当前生成并返回故事确认页，不再继续请求")

                    Spacer()

                    #if DEBUG
                    Button("测试超时") {
                        model.presentFailureForPreview()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PosterPalette.paperWhite.opacity(0.7))
                    .frame(minHeight: 44)
                    .accessibilityLabel("测试超时")
                    .accessibilityHint("预览生成失败界面")
                    #endif
                }
            }
        }
    }

    /// Upload / prepare → queued threshold.
    private var seedProgress: Double {
        min(model.generationProgress / 0.35, 1)
    }

    /// Queued / processing growth band.
    private var growthProgress: Double {
        max(0, min((model.generationProgress - 0.35) / 0.55, 1))
    }

    /// Final download / finish band.
    private var harvestProgress: Double {
        max(0, min((model.generationProgress - 0.9) / 0.1, 1))
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

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
        // Keep page chrome transparent so RootView's persistent source photo
        // remains visible inside HeroPhotoSlot while the target is generated.
        PosterScreenContainer(background: Color.clear) {
            VStack(alignment: .leading, spacing: PosterSpacing.lg) {
                VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                    Label("目标 \(model.generationTargetTime.compactLabel)", systemImage: "clock.arrow.2.circlepath")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PosterPalette.actionBlueDeep)

                    Text("照片先去往目标时间")
                        .font(PosterTypography.display(34))
                        .foregroundStyle(PosterPalette.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("在它回来之前，我们不会先写答案。")
                        .font(.subheadline)
                        .foregroundStyle(PosterPalette.mutedInk)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(yearText)
                        .font(PosterTypography.display(54))
                        .foregroundStyle(PosterPalette.actionBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: PosterSpacing.md)
                    Text(model.pipelineStatusText.isEmpty ? "准备出发" : model.pipelineStatusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PosterPalette.ink)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                }

                HeroPhotoSlot(
                    owner: .generating,
                    aspectRatio: photoAspectRatio,
                    maximumHeight: 280,
                    cornerRadius: PosterRadius.photoPaper
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PosterRadius.photoPaper, style: .continuous)
                        .stroke(PosterPalette.actionBlue.opacity(0.32), lineWidth: 1)
                }

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

                Button {
                    model.cancelGeneration()
                } label: {
                    Label("取消并返回相机", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PosterPalette.actionBlueDeep)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PosterPressStyle())
                .accessibilityHint("停止当前目标图片请求并回到取景页面")
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

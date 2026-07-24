import SwiftUI

struct StoryReadyView: View {
    let model: AppModel

    private var photoAspectRatio: CGFloat {
        CGFloat(model.capturedPhoto?.displayAspectRatio ?? 3.0 / 4.0)
    }

    var body: some View {
        PosterScreenContainer {
            VStack(alignment: .leading, spacing: PosterSpacing.lg) {
                PosterTitleView(
                    segments: ["故事", "已经", "醒来"],
                    color: PosterPalette.sky,
                    fontSize: 36
                )

                PhotoAspectContainer(
                    aspectRatio: photoAspectRatio,
                    maximumHeight: 320
                ) {
                    CapturedPhotoView(photo: model.capturedPhoto)
                        .overlay(alignment: .bottomLeading) {
                            Text(model.sceneUnderstanding?.locationType ?? "这一个地方")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PosterPalette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(PosterPalette.leafGreen)
                                .clipShape(Capsule())
                                .padding(PosterSpacing.md)
                        }
                }

                if let story = model.temporalStory {
                    VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                        Text(story.title)
                            .font(PosterTypography.display(32))
                            .foregroundStyle(PosterPalette.skyDeep)
                        Text(story.logline)
                            .font(.body.weight(.medium))
                            .foregroundStyle(PosterPalette.ink)
                    }

                    Text("目标照片 · \(model.generationTargetTime.compactLabel)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PosterPalette.skyDeep)
                        .padding(.horizontal, PosterSpacing.sm)
                        .padding(.vertical, PosterSpacing.xs)
                        .background(PosterPalette.leafGreen.opacity(0.45))
                        .clipShape(Capsule())

                    Text("浏览 AI 生成的过去 / 未来故事 · 不改变目标照片")
                        .font(.caption)
                        .foregroundStyle(PosterPalette.mutedInk)

                    TimeRail(
                        value: model.selectedTime.normalized,
                        onDetent: model.playTimeDetent
                    ) { value in
                        model.updateTime(normalized: value)
                    }

                    VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                        HStack {
                            Text(model.currentStoryBeat?.title ?? "今天的这里")
                                .font(.headline)
                            Spacer()
                            Text(model.selectedTime.compactLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PosterPalette.sky)
                        }
                        Text(model.currentNarrative)
                            .font(.body)
                            .foregroundStyle(PosterPalette.ink)
                    }
                    .padding(PosterSpacing.lg)
                    .background(PosterPalette.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: PosterRadius.card)
                            .stroke(PosterPalette.line, lineWidth: 1)
                    }
                }

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: "生成拍摄目标年份",
                        style: .lime,
                        accessibilityHint: "基于原图生成拍摄时锁定年份的照片；时间轴只用于浏览故事"
                    ) {
                        Task { await model.generateStoryWorld() }
                    }

                    PosterCapsuleButton(
                        title: "用浏览年份生成",
                        style: .secondary,
                        accessibilityHint: "将当前浏览的故事年份设为新目标，再生成一张照片"
                    ) {
                        Task { await model.generateAtStoryPreviewTime() }
                    }

                    Button {
                        Task { await model.regenerateStory() }
                    } label: {
                        Label("再写一个版本", systemImage: "arrow.trianglehead.2.clockwise")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PosterPalette.skyDeep)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PosterPressStyle())
                    .accessibilityHint("保留识图结果并重新编写时间故事")
                }
            }
        }
    }
}

#Preview {
    StoryReadyView(model: PreviewFixtures.model(phase: .storyReady, time: 0.35))
}

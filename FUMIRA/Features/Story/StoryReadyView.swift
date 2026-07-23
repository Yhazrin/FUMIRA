import SwiftUI

struct StoryReadyView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(alignment: .leading, spacing: PosterSpacing.lg) {
                PosterTitleView(
                    segments: ["故事", "已经", "醒来"],
                    color: PosterPalette.sky,
                    fontSize: 36
                )

                CapturedPhotoView(photo: model.capturedPhoto)
                    .frame(height: 230)
                    .overlay(alignment: .bottomLeading) {
                        Text(model.sceneUnderstanding?.locationType ?? "这一个地方")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PosterPalette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PosterPalette.moss)
                            .clipShape(Capsule())
                            .padding(PosterSpacing.md)
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

                    TimeRail(value: model.selectedTime.normalized) { value in
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
                    .background(PosterPalette.paperWhite)
                    .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card))
                }

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: "用这个故事生成",
                        style: .lime,
                        accessibilityHint: "基于原图和当前时间故事生成变迁图"
                    ) {
                        Task { await model.generateStoryWorld() }
                    }

                    PosterCapsuleButton(
                        title: "再写一个版本",
                        style: .secondary,
                        accessibilityHint: "保留识图结果并重新编写时间故事"
                    ) {
                        Task { await model.regenerateStory() }
                    }
                }
            }
        }
    }
}

#Preview {
    StoryReadyView(model: PreviewFixtures.model(phase: .storyReady, time: 0.35))
}

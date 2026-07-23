import SwiftUI

struct StoryWritingView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeYear = -100

    private let years = [-100, -30, -10, 0, 10, 30, 100]

    var body: some View {
        PosterScreenContainer(background: PosterPalette.pine) {
            VStack(alignment: .leading, spacing: PosterSpacing.xl) {
                PosterTitleView(
                    segments: ["让", "时间", "开口"],
                    color: PosterPalette.paperWhite,
                    fontSize: 38
                )

                if let understanding = model.sceneUnderstanding {
                    VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                        Text("AI 看见了")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PosterPalette.pine)
                            .textCase(.uppercase)
                        Text(understanding.summary)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(PosterPalette.ink)
                    }
                    .padding(PosterSpacing.lg)
                    .background(PosterPalette.paperWhite)
                    .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card))
                }

                HStack(spacing: 5) {
                    ForEach(years, id: \.self) { year in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(year == activeYear ? PosterPalette.moss : PosterPalette.paperWhite)
                                .frame(width: year == activeYear ? 20 : 10, height: year == activeYear ? 20 : 10)
                            Text(year == 0 ? "NOW" : String(format: "%+d", year))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(PosterPalette.paperWhite)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, PosterSpacing.lg)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(PosterPalette.paperWhite.opacity(0.35))
                        .frame(height: 2)
                        .offset(y: 9)
                }

                VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                    Text(model.pipelineStatusText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(PosterPalette.paperWhite)
                    ProgressView(value: model.storyProgress)
                        .tint(PosterPalette.moss)
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                    Text("故事模型正在把过去、现在与未来连成同一个地点的生命线。")
                        .font(.footnote)
                        .foregroundStyle(PosterPalette.paperWhite.opacity(0.72))
                }

                Spacer(minLength: PosterSpacing.lg)
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

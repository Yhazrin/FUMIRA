import SwiftUI

struct GenerationFailureView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.xl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(PosterPalette.errorCoral.opacity(0.18))
                        .frame(width: 120, height: 120)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(PosterPalette.errorCoral)
                }
                .accessibilityHidden(true)

                PosterTitleView(
                    segments: failureTitle,
                    color: PosterPalette.errorCoral,
                    fontSize: 34
                )

                Text(model.lastErrorMessage ?? "这一阶段暂时没有完成，前面的结果已经保留。")
                    .font(.body)
                    .foregroundStyle(PosterPalette.ink)
                    .multilineTextAlignment(.leading)

                Spacer()

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: retryTitle,
                        accessibilityHint: "从失败阶段继续，不重复已经完成的步骤"
                    ) {
                        Task { await model.retryPipeline() }
                    }

                    PosterCapsuleButton(
                        title: fallbackTitle,
                        style: .secondary,
                        accessibilityHint: "退出失败状态并保留已有内容"
                    ) {
                        model.showOriginalNow()
                    }
                }
            }
        }
    }

    private var failureTitle: [String] {
        switch model.failedStage {
        case .capture:
            ["快门", "没有", "留下照片"]
        case .understanding:
            ["还没", "完全", "看懂"]
        case .story:
            ["故事", "停在", "半路"]
        case .configuration:
            ["模型", "还没", "接好"]
        default:
            ["这一帧", "没赶上", "时间"]
        }
    }

    private var retryTitle: String {
        model.failedStage == .configuration ? "打开设置" : "从这里继续"
    }

    private var fallbackTitle: String {
        model.temporalStory == nil ? "重新拍摄" : "查看已有故事"
    }
}

#Preview {
    GenerationFailureView(model: PreviewFixtures.model(phase: .pipelineFailure))
}

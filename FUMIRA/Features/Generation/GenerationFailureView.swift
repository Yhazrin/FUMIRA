import SwiftUI

struct GenerationFailureView: View {
    let model: AppModel

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: ClaySpacing.xxxl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(ClayPalette.error.opacity(0.18))
                        .frame(width: 120, height: 120)
                    Image(systemName: failureSymbol)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(ClayPalette.error)
                }
                .accessibilityHidden(true)

                VStack(spacing: 4) {
                    ForEach(failureTitle.indices, id: \.self) { index in
                        Text(failureTitle[index])
                            .font(ClayTypography.displayLarge)
                            .foregroundStyle(ClayPalette.textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: ClaySpacing.sm) {
                    Text(failureMessage)
                        .font(ClayTypography.body)
                        .foregroundStyle(ClayPalette.textMuted)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                VStack(spacing: ClaySpacing.lg) {
                    if showsPrimaryRetry {
                        Button {
                            Task { await model.retryPipeline() }
                        } label: {
                            Text(retryTitle)
                                .font(ClayTypography.bodyBold)
                                .foregroundStyle(ClayPalette.charcoal)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .clayButtonStyle()
                    }

                    Button {
                        model.showOriginalNow()
                    } label: {
                        Text(fallbackTitle)
                            .font(ClayTypography.bodyBold)
                            .foregroundStyle(ClayPalette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        RoundedRectangle(cornerRadius: ClayShape.button, style: .continuous)
                            .stroke(ClayPalette.warmWhiteRim, lineWidth: 1.5)
                    }
                }
            }
        }
    }

    private var showsPrimaryRetry: Bool {
        model.failedStage == .configuration || model.canRetryFailedStage
    }

    private var failureSymbol: String {
        switch model.lastGenerationError {
        case .networkFailure, .serverUnavailable:
            "wifi.exclamationmark"
        case .rateLimited:
            "hourglass"
        case .timedOut:
            "clock.badge.exclamationmark"
        case .uploadFailure:
            "arrow.up.circle.badge.exclamationmark"
        case .invalidParameters:
            "slider.horizontal.3"
        default:
            "exclamationmark"
        }
    }

    private var failureMessage: String {
        switch model.lastGenerationError {
        case .timedOut:
            "等得太久了。"
        case .networkFailure:
            "网络没有接通。"
        case .uploadFailure:
            "照片没有送达。"
        case .invalidParameters:
            "这个时间暂时无法生成。"
        case .rateLimited:
            "服务正忙。"
        case .serverUnavailable:
            "时间通道暂时关闭。"
        case .generationFailed:
            "这一帧没有生成。"
        case nil:
            "已有内容已保留。"
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
        if model.failedStage == .configuration {
            return "打开设置"
        }
        if model.lastGenerationError == .rateLimited {
            return "稍后再试一次"
        }
        return "重试"
    }

    private var retryAccessibilityHint: String {
        if model.failedStage == .configuration {
            return "打开模型设置"
        }
        return "从失败阶段继续，不重复已经完成的步骤"
    }

    private var fallbackTitle: String {
        if model.canUndoGeneration {
            return "返回上一张结果"
        }
        return model.generatedFrame == nil ? "重新拍摄" : "查看已有结果"
    }
}

#Preview {
    GenerationFailureView(model: PreviewFixtures.model(phase: .pipelineFailure))
}

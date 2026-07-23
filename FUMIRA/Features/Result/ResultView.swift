import SwiftUI
import UIKit

struct ResultView: View {
    let model: AppModel
    var namespace: Namespace.ID

    var body: some View {
        ZStack {
            resultBackground
                .ignoresSafeArea()

            VStack {
                LinearGradient(
                    colors: [PosterPalette.canvas.opacity(0.92), PosterPalette.canvas.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .overlay(alignment: .top) {
                    PosterKeywordHero(moment: .reply, fontSize: 34)
                        .padding(.horizontal, PosterSpacing.lg)
                        .padding(.top, PosterSpacing.xl)
                }

                Spacer()

                VStack(spacing: PosterSpacing.md) {
                    VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                        HStack {
                            Text(model.currentStoryBeat?.title ?? "今天的这里")
                                .font(.headline)
                                .foregroundStyle(PosterPalette.skyDeep)
                            Spacer()
                            Text(model.selectedTime.compactLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PosterPalette.sky)
                        }
                        Text(model.currentNarrative)
                            .font(.footnote)
                            .foregroundStyle(PosterPalette.ink)
                            .lineLimit(4)
                            .contentTransition(.numericText())
                    }
                    .padding(PosterSpacing.md)
                    .background(PosterPalette.paperWhite.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card))
                    .padding(.horizontal, PosterSpacing.lg)

                    TimeRail(
                        value: model.selectedTime.normalized,
                        onDetent: model.playTimeDetent
                    ) { normalized in
                        model.updateTime(normalized: normalized)
                    }
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(.vertical, PosterSpacing.sm)

                    HStack(spacing: PosterSpacing.md) {
                        PosterCapsuleButton(
                            title: "保存海报",
                            accessibilityHint: "打开海报预览，可保存到相册或系统分享"
                        ) {
                            model.openShare()
                        }

                        PosterCapsuleButton(
                            title: "重新生成",
                            style: .lime,
                            accessibilityHint: "用同一张原图和当前时间位再生成一张"
                        ) {
                            Task { await model.regenerateResult() }
                        }
                    }
                    .padding(.horizontal, PosterSpacing.lg)

                    HStack(spacing: PosterSpacing.md) {
                        PosterCapsuleButton(
                            title: "重拍",
                            style: .secondary,
                            accessibilityHint: "返回取景器重新拍摄或导入"
                        ) {
                            model.retake()
                        }

                        if model.canUndoGeneration {
                            PosterCapsuleButton(
                                title: "撤销",
                                style: .secondary,
                                accessibilityHint: "恢复上一张生成结果"
                            ) {
                                model.undoLastGeneration()
                            }
                        }
                    }
                    .padding(.horizontal, PosterSpacing.lg)
                }
                .padding(.bottom, PosterSpacing.lg)
                .background(
                    LinearGradient(
                        colors: [PosterPalette.canvas.opacity(0), PosterPalette.canvas.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var resultBackground: some View {
        if let data = model.generatedFrame?.imageData,
           let image = UIImage(data: data)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .flatParallax(model.motionField, depth: .back)
                .accessibilityLabel("生成的时间场景")
        } else {
            TemporalParkScene(
                time: model.selectedTime,
                namespace: namespace,
                cornerRadius: 0,
                motionField: model.motionField
            )
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            ResultView(model: PreviewFixtures.model(phase: .result), namespace: namespace)
        }
    }
    return PreviewWrapper()
}

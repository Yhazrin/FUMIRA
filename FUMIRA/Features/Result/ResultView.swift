import SwiftUI

struct ResultView: View {
    let model: AppModel
    var namespace: Namespace.ID

    private var titleSegments: [String] {
        let years = model.selectedTime.offsetYears
        if abs(years) < 0.5 {
            return ["现在", "的", "这里"]
        }
        if years < 0 {
            return ["过去", "的", "这里"]
        }
        return ["未来", "的", "这里"]
    }

    var body: some View {
        ZStack {
            TemporalParkScene(
                time: model.selectedTime,
                namespace: namespace,
                cornerRadius: 0
            )
            .ignoresSafeArea()

            VStack {
                LinearGradient(
                    colors: [PosterPalette.paper.opacity(0.92), PosterPalette.paper.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                        PosterTitleView(
                            segments: titleSegments,
                            color: PosterPalette.timeBlue,
                            fontSize: 34
                        )
                        .padding(.horizontal, PosterSpacing.lg)
                        .padding(.top, PosterSpacing.xl)

                        Rectangle()
                            .fill(PosterPalette.energyLime)
                            .frame(width: 80, height: 4)
                            .padding(.horizontal, PosterSpacing.lg)
                    }
                }

                Spacer()

                VStack(spacing: PosterSpacing.md) {
                    VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                        HStack {
                            Text(model.currentStoryBeat?.title ?? "今天的这里")
                                .font(.headline)
                                .foregroundStyle(PosterPalette.deepTimeBlue)
                            Spacer()
                            Text(model.selectedTime.compactLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PosterPalette.timeBlue)
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

                    TimeRail(value: model.selectedTime.normalized) { normalized in
                        model.updateTime(normalized: normalized)
                    }
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(.vertical, PosterSpacing.md)
                    .background(PosterPalette.paper.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))

                    HStack(spacing: PosterSpacing.md) {
                        PosterCapsuleButton(
                            title: "保存海报",
                            accessibilityHint: "打开分享预览"
                        ) {
                            model.openShare()
                        }

                        PosterCapsuleButton(
                            title: "重拍",
                            style: .secondary,
                            accessibilityHint: "返回取景器重新拍摄"
                        ) {
                            model.retake()
                        }
                    }
                    .padding(.horizontal, PosterSpacing.lg)
                }
                .padding(.bottom, PosterSpacing.lg)
                .background(
                    LinearGradient(
                        colors: [PosterPalette.paper.opacity(0), PosterPalette.paper.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
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

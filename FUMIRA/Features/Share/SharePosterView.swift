import SwiftUI

struct SharePosterView: View {
    let model: AppModel

    private var yearLabel: String {
        let years = model.selectedTime.offsetYears
        if abs(years) < 0.5 { return "NOW" }
        return String(format: "%+.0f 年", years)
    }

    var body: some View {
        PosterScreenContainer {
            VStack(spacing: PosterSpacing.lg) {
                PosterTitleView(
                    segments: ["带走", "这段", "时间"],
                    color: PosterPalette.sky,
                    fontSize: 36
                )

                VStack(spacing: 0) {
                    TemporalParkScene(time: model.selectedTime)
                        .frame(height: 280)

                    VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                        Text(yearLabel)
                            .font(PosterTypography.display(32))
                            .foregroundStyle(PosterPalette.sky)
                        Text(model.temporalStory?.title ?? "这一刻的时间故事")
                            .font(.headline)
                            .foregroundStyle(PosterPalette.ink)
                        Text(model.currentNarrative)
                            .font(.footnote)
                            .foregroundStyle(PosterPalette.mutedInk)
                            .lineLimit(5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PosterSpacing.lg)
                    .background(PosterPalette.paperWhite)
                }
                .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
                .shadow(color: PosterEffects.floating, radius: 16, y: 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("时间海报")
                .accessibilityValue("\(model.selectedTime.compactLabel)，\(model.currentNarrative)")

                Spacer()

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: "分享海报",
                        accessibilityHint: "Mock 模式下仅展示分享按钮样式"
                    ) {
                        // Mock share — no system sheet in MVP scope
                    }

                    PosterCapsuleButton(
                        title: "返回浏览",
                        style: .secondary,
                        accessibilityHint: "回到结果页继续调整时间"
                    ) {
                        model.returnToResult()
                    }
                }
            }
        }
    }
}

#Preview {
    SharePosterView(model: PreviewFixtures.model(phase: .share, time: 0.35))
}

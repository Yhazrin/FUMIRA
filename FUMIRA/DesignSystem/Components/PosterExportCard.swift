import SwiftUI
import UIKit

/// Flat poster composition for on-screen preview and PNG export.
/// Paper card + scene hero + story copy; no blue-purple AI gradients.
struct PosterExportCard: View {
    let time: TimePosition
    let yearLabel: String
    let title: String
    let narrative: String
    var sceneImage: UIImage?
    var interpretationTrace: TemporalInterpretationTrace?

    private var resolvedTrace: TemporalInterpretationTrace {
        interpretationTrace ?? .resolve(
            story: nil,
            understanding: nil,
            at: time
        )
    }

    private var displayedNarrative: String {
        narrative
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
                .frame(maxWidth: .infinity)
                .frame(height: 340)

            VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: PosterSpacing.md) {
                        selectedTimeLabel
                        Spacer(minLength: PosterSpacing.sm)
                        interpretationLabel
                    }

                    VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                        interpretationLabel
                        selectedTimeLabel
                    }
                }

                Text(title)
                    .font(PosterTypography.cardTitle)
                    .foregroundStyle(PosterPalette.ink)
                    .lineLimit(2)

                Text(displayedNarrative)
                    .font(PosterTypography.supporting)
                    .foregroundStyle(PosterPalette.mutedInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: PosterSpacing.sm)

                HStack(alignment: .bottom, spacing: PosterSpacing.md) {
                    TemporalFingerprintMark(
                        markers: resolvedTrace.markers,
                        selectedTime: time,
                        size: .poster
                    )

                    Spacer(minLength: PosterSpacing.sm)

                    Text("FUMIRA")
                        .font(PosterTypography.script(22))
                        .foregroundStyle(PosterPalette.skyDeep)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(PosterSpacing.lg)
            .background(PosterPalette.paperWhite)
        }
        .background(PosterPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("时间海报")
        .accessibilityValue(
            "\(yearLabel)，一种可能的时间解释，\(title)，\(displayedNarrative)，确定性时间指纹"
        )
    }

    private var selectedTimeLabel: some View {
        Text(yearLabel)
            .font(PosterTypography.display(36))
            .foregroundStyle(PosterPalette.skyDeep)
            .accessibilityAddTraits(.isHeader)
    }

    private var interpretationLabel: some View {
        Text("一种可能的时间解释")
            .font(PosterTypography.caption)
            .foregroundStyle(PosterPalette.actionBlueDeep)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            if let sceneImage {
                Image(uiImage: sceneImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                TemporalParkScene(
                    time: time,
                    cornerRadius: 0
                )
            }

            Circle()
                .stroke(PosterPalette.leafGreen.opacity(0.75), lineWidth: 2.5)
                .frame(width: 22, height: 22)
                .padding(PosterSpacing.md)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Poster export card") {
    PosterExportCard(
        time: TimePosition(normalized: 0.35),
        yearLabel: "+12 年",
        title: "公园会记得你",
        narrative: "同一条小路，树影更长了一些。风还在，人也还在。"
    )
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

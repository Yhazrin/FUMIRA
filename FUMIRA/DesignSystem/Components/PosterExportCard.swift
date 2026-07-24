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

    var body: some View {
        VStack(spacing: 0) {
            hero
                .frame(maxWidth: .infinity)
                .frame(height: 340)

            VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                Text(yearLabel)
                    .font(PosterTypography.display(36))
                    .foregroundStyle(PosterPalette.skyDeep)
                    .accessibilityAddTraits(.isHeader)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PosterPalette.ink)
                    .lineLimit(2)

                Text(narrative)
                    .font(.subheadline)
                    .foregroundStyle(PosterPalette.mutedInk)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: PosterSpacing.sm)

                HStack(alignment: .lastTextBaseline) {
                    Text("FUMIRA")
                        .font(PosterTypography.script(22))
                        .foregroundStyle(PosterPalette.skyDeep)
                    Spacer()
                    Text("时间相机")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PosterPalette.skyDeep.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(PosterSpacing.lg)
            .background(PosterPalette.paperWhite)
        }
        .background(PosterPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                .stroke(PosterPalette.skyDeep.opacity(0.22), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("时间海报")
        .accessibilityValue("\(yearLabel)，\(title)，\(narrative)")
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

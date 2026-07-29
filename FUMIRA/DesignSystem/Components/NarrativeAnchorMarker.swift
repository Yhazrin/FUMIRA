import SwiftUI

/// Marks the point the person asked FUMIRA to treat as the emotional center of
/// the time story. It remains visually light so the whole scene still reads as
/// the generation scope.
struct NarrativeAnchorMarker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(PosterPalette.bellYellow.opacity(0.45), lineWidth: 1)
                .frame(width: 62, height: 62)

            Circle()
                .stroke(
                    PosterPalette.bellYellow,
                    style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                )
                .frame(width: 44, height: 44)

            Circle()
                .fill(PosterPalette.bellYellow)
                .frame(width: 8, height: 8)

            Text("时间主体")
                .font(.caption2.weight(.black))
                .foregroundStyle(PosterPalette.ink)
                .padding(.horizontal, PosterSpacing.sm)
                .frame(minHeight: 24)
                .background(PosterPalette.bellYellow, in: Capsule())
                .offset(y: -46)
        }
        .shadow(color: PosterPalette.ink.opacity(0.28), radius: 5, y: 2)
        .transition(
            reduceMotion
                ? .opacity
                : .scale(scale: 0.82).combined(with: .opacity)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("viewfinder.subject-anchor")
        .accessibilityLabel("时间主体已选择")
        .accessibilityHint("生成故事会优先围绕这里展开，但整个场景仍会随时间变化")
    }
}

#Preview {
    ZStack {
        PosterPalette.skyDeep
        NarrativeAnchorMarker()
    }
}

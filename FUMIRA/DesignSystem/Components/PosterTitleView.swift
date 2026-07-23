import SwiftUI

struct PosterTitleView: View {
    let segments: [String]
    var color: Color = PosterPalette.sky
    var fontSize: CGFloat = 42
    var rotations: [Double] = [-2, 3, -1.5, 2.5]

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Text(segment)
                    .font(PosterTypography.display(fontSize))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(rotation(for: index)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func rotation(for index: Int) -> Double {
        guard index < rotations.count else { return 0 }
        return rotations[index]
    }
}

struct PosterScriptSubtitle: View {
    let text: String
    var color: Color = PosterPalette.mutedInk

    var body: some View {
        Text(text)
            .font(PosterTypography.script(22))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

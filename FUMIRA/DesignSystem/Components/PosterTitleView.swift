import SwiftUI

enum PosterTitleLayout {
    case compact
    case stacked
}

struct PosterTitleView: View {
    let segments: [String]
    var color: Color = PosterPalette.sky
    var fontSize: CGFloat = 42
    var rotations: [Double] = [-2, 3, -1.5, 2.5]
    var layout: PosterTitleLayout = .compact

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .lastTextBaseline, spacing: PosterSpacing.sm) {
                    ForEach(row.indices, id: \.self) { column in
                        let item = row[column]
                        Text(item.segment)
                            .font(PosterTypography.display(fontSize))
                            .foregroundStyle(color)
                            .rotationEffect(.degrees(rotation(for: item.index)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var rows: [[(index: Int, segment: String)]] {
        let indexed = Array(segments.enumerated()).map {
            (index: $0.offset, segment: $0.element)
        }
        guard layout == .compact else {
            return indexed.map { [$0] }
        }
        guard indexed.count > 2 else {
            return indexed.isEmpty ? [] : [indexed]
        }

        return stride(from: 0, to: indexed.count, by: 2).map { start in
            Array(indexed[start..<min(start + 2, indexed.count)])
        }
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

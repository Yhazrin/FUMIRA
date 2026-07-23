import SwiftUI

struct GenerationProgressRow: View {
    let title: String
    let progress: Double
    var isComplete: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PosterPalette.paperWhite)
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PosterPalette.moss)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PosterPalette.paperWhite.opacity(0.25))
                    Capsule()
                        .fill(PosterPalette.moss)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                        .animation(PosterMotion.flow, value: progress)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isComplete ? "已完成" : "\(Int(progress * 100))%")
    }
}

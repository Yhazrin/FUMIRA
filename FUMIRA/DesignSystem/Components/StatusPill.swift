import SwiftUI

struct StatusPill: View {
    let icon: String
    let label: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: PosterSpacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(PosterPalette.ink)
        .padding(.horizontal, PosterSpacing.md)
        .padding(.vertical, PosterSpacing.sm)
        .background(isActive ? PosterPalette.leafGreen : PosterPalette.canvas)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(isActive ? PosterPalette.leafGreen.opacity(0.35) : PosterPalette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

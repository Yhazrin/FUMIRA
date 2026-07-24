import SwiftUI

enum PosterCapsuleStyle {
    case primary
    case secondary
    case lime
}

struct PosterCapsuleButton: View {
    let title: String
    var style: PosterCapsuleStyle = .primary
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(background)
                .clipShape(Capsule())
        }
        .buttonStyle(PosterCapsulePressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            PosterPalette.ink
        case .lime:
            // Accent chip style: leaf-green fill + ink label (never fluorescent full-bleed)
            PosterPalette.ink
        case .secondary:
            PosterPalette.skyDeep
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            // Match shutter energy: fresh leaf green, not dark pine.
            PosterPalette.leafGreen
        case .secondary:
            PosterPalette.skyDeep.opacity(0.12)
        case .lime:
            PosterPalette.leafGreen
        }
    }
}

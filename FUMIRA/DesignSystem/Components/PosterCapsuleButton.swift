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
                .overlay {
                    if style == .secondary {
                        Capsule()
                            .stroke(PosterPalette.ink, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(PosterCapsulePressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .lime:
            style == .lime ? PosterPalette.ink : PosterPalette.paperWhite
        case .secondary:
            PosterPalette.ink
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            PosterPalette.ink
        case .secondary:
            Color.clear
        case .lime:
            PosterPalette.energyLime
        }
    }
}

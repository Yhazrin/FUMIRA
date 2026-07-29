import SwiftUI

enum PosterCapsuleStyle {
    case primary
    case secondary
    case accent
}

struct PosterCapsuleButton: View {
    let title: String
    var style: PosterCapsuleStyle = .primary
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PosterTypography.button)
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(background)
                .clipShape(Capsule())
        }
        .buttonStyle(PosterCapsulePressStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .accent:
            PosterPalette.paperWhite
        case .secondary:
            PosterPalette.actionBlueDeep
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            PosterPalette.actionBlue
        case .secondary:
            PosterPalette.actionBlue.opacity(0.12)
        case .accent:
            PosterPalette.actionBlueDeep
        }
    }
}

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
        }
        .clayButtonStyle(
            base: baseColor,
            rim: rimColor,
            foreground: foregroundColor,
            cornerRadius: ClayShape.pill,
            depth: 5
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            ClayPalette.warmWhite
        case .secondary:
            ClayPalette.timeBlueRim
        case .accent:
            ClayPalette.charcoal
        }
    }

    private var baseColor: Color {
        switch style {
        case .primary:
            ClayPalette.timeBlue
        case .secondary:
            ClayPalette.warmWhite
        case .accent:
            ClayPalette.orange
        }
    }

    private var rimColor: Color {
        switch style {
        case .primary:
            ClayPalette.timeBlueRim
        case .secondary:
            ClayPalette.warmWhiteRim
        case .accent:
            ClayPalette.orangeDepth
        }
    }
}

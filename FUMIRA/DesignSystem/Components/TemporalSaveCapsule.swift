import SwiftUI

/// Result-only primary action. The photo reveal now resolves into a discrete,
/// raised Time Blue key instead of washing a generic gradient across the label.
struct TemporalSaveCapsule: View {
    let title: String
    let revealProgress: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var settledProgress: CGFloat {
        reduceMotion ? 1 : FUMIRASpatialMotion.clamp(revealProgress)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: PosterSpacing.md) {
                VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                    Text(title)
                        .font(PosterTypography.button)
                        .fixedSize(horizontal: false, vertical: true)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("FUMIRA")
                            .font(PosterTypography.caption)
                            .foregroundStyle(PosterPalette.mutedInk)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: PosterSpacing.sm)

                ClayMoldedControl(
                    base: ClayPalette.timeBlue,
                    rim: ClayPalette.timeBlueRim,
                    foreground: ClayPalette.warmWhite,
                    cornerRadius: ClayShape.pill,
                    depth: 3,
                    isPressed: false
                ) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .scaleEffect(0.94 + settledProgress * 0.06)
                .opacity(0.76 + settledProgress * 0.24)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, PosterSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PosterSpacing.lg + PosterSpacing.xl)
        }
        .clayButtonStyle(
            base: ClayPalette.warmWhite,
            rim: ClayPalette.warmWhiteRim,
            foreground: PosterPalette.ink,
            cornerRadius: ClayShape.pill,
            depth: 5
        )
        .accessibilityLabel(title)
        .accessibilityHint("打开海报预览，可保存到相册或系统分享")
    }
}

#Preview("Temporal save capsule") {
    TemporalSaveCapsule(
        title: "保存海报",
        revealProgress: 1,
        reduceMotion: false,
        action: {}
    )
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

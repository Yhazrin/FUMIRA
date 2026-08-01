import SwiftUI

/// Clay icon button — small round or squircle button for SF Symbols.
struct ClayIconButton: View {
    let systemName: String
    let base: Color
    let rim: Color
    let foreground: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void

    init(
        systemName: String,
        base: Color = ClayPalette.warmWhite,
        rim: Color = ClayPalette.warmWhiteRim,
        foreground: Color = ClayPalette.charcoal,
        size: CGFloat = 44,
        cornerRadius: CGFloat = ClayShape.sm,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.base = base
        self.rim = rim
        self.foreground = foreground
        self.size = size
        self.cornerRadius = cornerRadius
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .bold))
                .frame(width: size, height: size)
        }
        .clayButtonStyle(
            base: base,
            rim: rim,
            foreground: foreground,
            cornerRadius: cornerRadius,
            depth: 4
        )
    }
}

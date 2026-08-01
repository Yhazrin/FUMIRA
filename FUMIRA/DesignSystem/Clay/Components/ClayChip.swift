import SwiftUI

/// Clay chip — small status or label pill.
struct ClayChip: View {
    let title: String
    let isActive: Bool
    let activeColor: Color
    let activeRim: Color

    init(
        _ title: String,
        isActive: Bool = false,
        activeColor: Color = ClayPalette.yellow,
        activeRim: Color = ClayPalette.yellowRim
    ) {
        self.title = title
        self.isActive = isActive
        self.activeColor = activeColor
        self.activeRim = activeRim
    }

    var body: some View {
        Text(title)
            .font(ClayTypography.chipLabel)
            .foregroundStyle(isActive ? ClayPalette.textOnAccent : ClayPalette.textMuted)
            .padding(.horizontal, ClaySpacing.chipHorizontal)
            .padding(.vertical, ClaySpacing.chipVertical)
            .background {
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(activeRim)
                            .offset(y: 2)
                    }
                    Capsule()
                        .fill(isActive ? activeColor : ClayPalette.charcoal.opacity(0.08))
                        .overlay(alignment: .top) {
                            Capsule()
                                .stroke(.white.opacity(isActive ? 0.32 : 0.14), lineWidth: 1)
                        }
                }
            }
    }
}

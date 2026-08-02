import SwiftUI

/// Clay segmented control — a physical toggle between options.
struct ClaySegmentedControl: View {
    let options: [String]
    @Binding var selectedIndex: Int

    init(options: [String], selectedIndex: Binding<Int>) {
        self.options = options
        self._selectedIndex = selectedIndex
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    withAnimation(ClayMotion.toggleSpring) {
                        selectedIndex = index
                    }
                } label: {
                    Text(options[index])
                        .font(ClayTypography.labelSmall)
                        .foregroundStyle(
                            selectedIndex == index
                                ? ClayPalette.textOnAccent
                                : ClayPalette.textMuted
                        )
                        .padding(.horizontal, ClaySpacing.lg)
                        .padding(.vertical, ClaySpacing.sm)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selectedIndex == index {
                                RoundedRectangle(cornerRadius: ClayShape.sm, style: .continuous)
                                    .fill(ClayPalette.orange)
                                    .overlay {
                                        ClayNoiseTexture(opacity: 0.12)
                                            .clipShape(RoundedRectangle(cornerRadius: ClayShape.sm, style: .continuous))
                                    }
                                    .shadow(
                                        color: ClayShadow.small.color,
                                        radius: ClayShadow.small.radius,
                                        x: ClayShadow.small.x,
                                        y: ClayShadow.small.y
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: ClayShape.md, style: .continuous)
                .fill(ClayPalette.charcoal.opacity(0.08))
        }
    }
}

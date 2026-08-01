import SwiftUI

/// Clay terminal — monospaced display for reconstruction progress,
/// model stages, coordinates, and system states.
struct ClayTerminal<Content: View>: View {
    let title: String
    let content: Content

    init(
        _ title: String = "STATUS",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ClayPanel(
            base: ClayPalette.charcoal,
            rim: ClayPalette.charcoalLight,
            cornerRadius: ClayShape.panel
        ) {
            VStack(alignment: .leading, spacing: ClaySpacing.stackDefault) {
                // Header
                HStack(spacing: 8) {
                    Circle()
                        .fill(ClayPalette.orange)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(ClayPalette.lime)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(ClayPalette.yellow)
                        .frame(width: 8, height: 8)

                    Spacer()

                    Text(title)
                        .font(ClayTypography.monoSmall)
                        .foregroundStyle(ClayPalette.textOnDark.opacity(0.55))
                }

                // Content
                content
            }
        }
    }
}

/// A single terminal line with prefix and value.
struct ClayTerminalLine: View {
    let prefix: String
    let value: String
    let valueColor: Color

    init(
        _ prefix: String,
        value: String,
        valueColor: Color = ClayPalette.lime
    ) {
        self.prefix = prefix
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(prefix)
                .font(ClayTypography.terminalCode)
                .foregroundStyle(ClayPalette.orange)

            Text(value)
                .font(ClayTypography.terminalCode)
                .foregroundStyle(valueColor)
        }
    }
}

/// Terminal screen — dark inset display area.
struct ClayTerminalScreen: View {
    let content: () -> AnyView

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        self.content = { AnyView(content()) }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: ClayShape.screen, style: .continuous)
            .fill(ClayPalette.charcoal)
            .overlay {
                ClayNoiseTexture(opacity: 0.10)
                    .clipShape(RoundedRectangle(cornerRadius: ClayShape.screen, style: .continuous))
            }
            .overlay {
                content()
                    .padding(ClaySpacing.screenPadding)
            }
            .shadow(
                color: ClayShadow.card.color,
                radius: ClayShadow.card.radius,
                x: ClayShadow.card.x,
                y: ClayShadow.card.y
            )
    }
}

import SwiftUI

/// Full-screen 3D clay diorama viewer.
/// Wraps the Three.js scene with native Clay OS controls.
struct DioramaView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var timeValue: Double = 0
    @State private var selectedEntityID: String?
    @State private var showEntityInfo = false
    @State private var isControlsVisible = true

    var body: some View {
        ZStack {
            ClayPalette.charcoal
                .ignoresSafeArea()

            // Three.js diorama
            DioramaWebView(
                timeValue: $timeValue,
                selectedEntityID: $selectedEntityID,
                onEntitySelected: { id in
                    withAnimation(ClayMotion.hoverSpring) {
                        selectedEntityID = id
                        showEntityInfo = true
                    }
                }
            )
            .ignoresSafeArea()

            // Top chrome
            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .opacity(isControlsVisible ? 1 : 0)
            .animation(ClayMotion.hoverSpring, value: isControlsVisible)

            // Entity info card
            if showEntityInfo, let entityID = selectedEntityID {
                entityInfoCard(entityID)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, ClaySpacing.xxl)
                    .padding(.top, 80)
            }
        }
        .preferredColorScheme(.dark)
        .onTapGesture(count: 2) {
            withAnimation { isControlsVisible.toggle() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ClayPalette.textOnDark)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(ClayPalette.charcoal.opacity(0.6))
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("CLAY DIORAMA")
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(0.5))
                Text("Campus Gate")
                    .font(ClayTypography.labelSmall)
                    .foregroundStyle(ClayPalette.textOnDark)
            }

            Spacer()

            // Placeholder for future share button
            Circle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, ClaySpacing.xxl)
        .padding(.top, 8)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: ClaySpacing.lg) {
            // Time display
            HStack {
                Text("TIME")
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(0.4))
                Spacer()
                Text(formatTime(timeValue))
                    .font(ClayTypography.monoLarge)
                    .foregroundStyle(ClayPalette.orange)
            }
            .padding(.horizontal, ClaySpacing.xxxl)

            // Time slider
            ClayTimeDial(
                value: $timeValue,
                range: -1...1,
                label: ""
            )
            .padding(.horizontal, ClaySpacing.xxl)

            // Continuous time range hint
            HStack {
                Text("-100y")
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(0.25))
                Spacer()
                Text("NOW")
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(abs(timeValue) < 0.03 ? 0.6 : 0.25))
                Spacer()
                Text("+100y")
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(0.25))
            }
            .padding(.horizontal, ClaySpacing.xxxl)
            .padding(.bottom, ClaySpacing.xxl)
        }
        .padding(.vertical, ClaySpacing.xxl)
        .background {
            LinearGradient(
                colors: [
                    .clear,
                    ClayPalette.charcoal.opacity(0.85),
                    ClayPalette.charcoal.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Entity info

    @ViewBuilder
    private func entityInfoCard(_ entityID: String) -> some View {
        ClayPanel(
            base: ClayPalette.charcoal.opacity(0.92),
            rim: ClayPalette.charcoalLight,
            cornerRadius: ClayShape.card
        ) {
            VStack(alignment: .leading, spacing: ClaySpacing.sm) {
                HStack {
                    Circle()
                        .fill(entityColor(entityID))
                        .frame(width: 10, height: 10)
                    Text(entityType(entityID))
                        .font(ClayTypography.monoTiny)
                        .foregroundStyle(ClayPalette.textOnDark.opacity(0.5))
                }

                Text(entityID)
                    .font(ClayTypography.subheading)
                    .foregroundStyle(ClayPalette.textOnDark)

                Divider()
                    .background(ClayPalette.warmWhite.opacity(0.1))

                Text(entityDescription(entityID))
                    .font(ClayTypography.bodySmall)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(0.6))

                // Temporal behaviors
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME BEHAVIORS")
                        .font(ClayTypography.monoTiny)
                        .foregroundStyle(ClayPalette.orange.opacity(0.7))
                    ForEach(entityBehaviors(entityID), id: \.self) { behavior in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ClayPalette.lime)
                                .frame(width: 4, height: 4)
                            Text(behavior)
                                .font(ClayTypography.monoSmall)
                                .foregroundStyle(ClayPalette.textOnDark.opacity(0.5))
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(width: 200)
        }
        .onTapGesture {
            withAnimation { showEntityInfo = false }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ p: Double) -> String {
        if abs(p) < 0.03 { return "NOW" }
        let days = p.sign == .minus
            ? -36525 * pow(abs(p), 2.35)
            : 36525 * pow(abs(p), 2.35)
        let years = days / 365.25
        if abs(years) < 1 {
            let months = Int(years * 12)
            return months > 0 ? "+\(months)mo" : "\(months)mo"
        }
        let y = Int(years.rounded())
        return y > 0 ? "+\(y)y" : "\(y)y"
    }

    private func entityColor(_ id: String) -> Color {
        if id.contains("gate") || id.contains("building") { return ClayPalette.orange }
        if id.contains("tree") { return ClayPalette.lime }
        if id.contains("person") { return ClayPalette.yellow }
        return ClayPalette.warmWhite
    }

    private func entityType(_ id: String) -> String {
        if id.contains("gate") || id.contains("building") { return "ARCHITECTURE" }
        if id.contains("tree") { return "VEGETATION" }
        if id.contains("person") { return "CHARACTER" }
        return "PROP"
    }

    private func entityDescription(_ id: String) -> String {
        if id.contains("gate") { return "Campus main gate with arched entrance, orange sign board, and symmetric facade." }
        if id.contains("tree") { return "Clay tree with seasonal foliage. Growth and color respond to time." }
        if id.contains("person") { return "Clay figurine with cloth and pose. Moves through the scene over time." }
        return "Scene object."
    }

    private func entityBehaviors(_ id: String) -> [String] {
        if id.contains("gate") || id.contains("building") {
            return ["WEATHERING", "RENOVATION", "SIGNAGE"]
        }
        if id.contains("tree") {
            return ["GROWTH", "SEASONAL FOLIAGE", "WIND RESPONSE"]
        }
        if id.contains("person") {
            return ["MOVEMENT", "AGING", "CLOTHING"]
        }
        return []
    }
}

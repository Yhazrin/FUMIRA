import SwiftUI

struct ConnectionFeedbackView: View {
    let model: AppModel
    let snapshot: HardwareSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            ClayAppBackground()
                .ignoresSafeArea()

            VStack(spacing: ClaySpacing.xxxl) {
                Spacer(minLength: ClaySpacing.xxl)

                Text("已连接")
                    .font(ClayTypography.displaySmall)
                    .foregroundStyle(ClayPalette.textPrimary)

                connectionCard
                    .padding(.horizontal, ClaySpacing.xxl)

                Spacer()

                Button {
                    model.continueFromConnection()
                } label: {
                    Text("继续")
                        .font(ClayTypography.bodyBold)
                        .foregroundStyle(ClayPalette.charcoal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .clayButtonStyle()
                .padding(.horizontal, ClaySpacing.xxl)
                .padding(.bottom, ClaySpacing.xxxl)
            }
        }
        .animation(
            reduceMotion
                ? .linear(duration: ClayMotion.durationFast)
                : ClayMotion.panelSpring,
            value: snapshot.batteryLevel
        )
    }

    private var connectionCard: some View {
        ClayPanel {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: ClaySpacing.lg) {
                        HStack(alignment: .firstTextBaseline, spacing: ClaySpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ClayPalette.lime)

                            Text(displayNameParts.primary)
                                .foregroundStyle(ClayPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                        .font(.headline.weight(.bold))

                        HStack(spacing: ClaySpacing.sm) {
                            if let secondary = displayNameParts.secondary {
                                Text(secondary)
                                    .font(.body.weight(.semibold))
                            }

                            Spacer(minLength: 0)

                            Label("\(snapshot.batteryLevel)%", systemImage: "battery.75")
                                .font(.body.monospacedDigit().weight(.semibold))
                        }
                        .foregroundStyle(ClayPalette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: ClaySpacing.lg) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(ClayPalette.lime)

                        Text(displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ClayPalette.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: ClaySpacing.sm)

                        Label("\(snapshot.batteryLevel)%", systemImage: "battery.75")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ClayPalette.textPrimary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(snapshot.name) 已连接，电量 \(snapshot.batteryLevel)%"
        )
    }

    private var displayName: String {
        snapshot.name.replacingOccurrences(of: "_", with: " ")
    }

    private var displayNameParts: (primary: String, secondary: String?) {
        guard let separator = snapshot.name.firstIndex(of: "_") else {
            return (snapshot.name, nil)
        }
        let primary = String(snapshot.name[..<separator])
        let suffixStart = snapshot.name.index(after: separator)
        let secondary = String(snapshot.name[suffixStart...])
        return (primary, secondary.isEmpty ? nil : secondary)
    }
}

#Preview {
    ConnectionFeedbackView(
        model: PreviewFixtures.model(phase: .connected),
        snapshot: HardwareSnapshot(name: "FutureCam_01", batteryLevel: 86)
    )
}

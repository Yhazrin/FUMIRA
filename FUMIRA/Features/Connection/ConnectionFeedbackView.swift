import SwiftUI

struct ConnectionFeedbackView: View {
    let model: AppModel
    let snapshot: HardwareSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            PosterPalette.canvas.ignoresSafeArea()

            LinearGradient(
                colors: [
                    PosterPalette.sky.opacity(0.42),
                    PosterPalette.canvas,
                    PosterPalette.grassLight.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: PosterSpacing.xl) {
                Spacer(minLength: PosterSpacing.lg)

                PosterKeywordHero(
                    moment: .connecting,
                    fontSize: 32,
                    showsScriptLabel: false
                )
                    .padding(.horizontal, PosterSpacing.lg)

                connectionCard
                    .padding(.horizontal, PosterSpacing.lg)

                Spacer()

                PosterCapsuleButton(
                    title: "继续",
                    accessibilityHint: "进入相机权限步骤"
                ) {
                    model.continueFromConnection()
                }
                .padding(.horizontal, PosterSpacing.lg)
                .padding(.bottom, PosterSpacing.xl)
            }
        }
        .animation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : .spring(response: PosterMotion.poster, dampingFraction: 0.86),
            value: snapshot.batteryLevel
        )
    }

    private var connectionCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PosterSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: PosterSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PosterPalette.actionBlueDeep)

                        Text(displayNameParts.primary)
                            .foregroundStyle(PosterPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                    .font(.headline.weight(.bold))

                    HStack(spacing: PosterSpacing.sm) {
                        if let secondary = displayNameParts.secondary {
                            Text(secondary)
                                .font(.body.weight(.semibold))
                        }

                        Spacer(minLength: 0)

                        Label("\(snapshot.batteryLevel)%", systemImage: "battery.75")
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(PosterPalette.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: PosterSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(PosterPalette.actionBlueDeep)

                    Text(displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PosterPalette.ink)
                        .lineLimit(1)

                    Spacer(minLength: PosterSpacing.sm)

                    Label("\(snapshot.batteryLevel)%", systemImage: "battery.75")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(PosterPalette.ink)
                }
            }
        }
        .padding(PosterSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(PosterPalette.cardActive)
        .clipShape(
            RoundedRectangle(
                cornerRadius: PosterRadius.card,
                style: .continuous
            )
        )
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

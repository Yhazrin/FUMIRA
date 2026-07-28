import SwiftUI

struct ConnectionView: View {
    let model: AppModel

    @State private var didAppear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ParkPosterBackdrop(motionField: model.motionField)

            VStack(alignment: .leading, spacing: 0) {
                FUMIRAWordmark()
                    .padding(.top, 64)
                    .flatMotionEntrance(isVisible: didAppear, reduceMotion: reduceMotion)

                PosterKeywordHero(moment: .invite, fontSize: 46)
                    .padding(.top, PosterSpacing.xl)
                    .flatMotionEntrance(
                        isVisible: didAppear,
                        reduceMotion: reduceMotion,
                        delay: .milliseconds(90)
                    )

                Spacer(minLength: 0)

                PosterGlassButton(
                    title: "进入时间相机",
                    systemImage: "camera.aperture",
                    accessibilityHint: "打开相机，拍下一张给时间的照片",
                    action: { model.beginPhoneOnlyPath() }
                )
                .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
                .frame(maxWidth: .infinity, alignment: .center)
                .flatMotionEntrance(
                    isVisible: didAppear,
                    reduceMotion: reduceMotion,
                    delay: .milliseconds(220)
                )
                .padding(.bottom, 62)
            }
            .padding(.horizontal, PosterSpacing.lg)
        }
        .onAppear {
            didAppear = true
        }
    }
}

private struct FUMIRAWordmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array("FUMIRA".enumerated()), id: \.offset) { index, character in
                    Text(String(character))
                        .font(PosterTypography.script(78))
                        .tracking(1.2)
                        .foregroundStyle(PosterPalette.ink)
                        .rotationEffect(.degrees(-2.5), anchor: .leading)
                        .posterStaggerEntrance(
                            isVisible: didAppear,
                            index: index,
                            reduceMotion: reduceMotion
                        )
                }
            }

            HStack(spacing: PosterSpacing.sm) {
                Capsule()
                    .fill(PosterPalette.leafGreen)
                    .frame(width: 54, height: 5)
                Text("TIME CAMERA")
                    .font(.caption2.weight(.bold))
                    .tracking(2.1)
                    .foregroundStyle(PosterPalette.skyDeep.opacity(0.85))
                    .posterStaggerEntrance(
                        isVisible: didAppear,
                        index: 6,
                        reduceMotion: reduceMotion
                    )
            }
            .padding(.top, -6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FUMIRA 时间相机")
        .onAppear {
            didAppear = true
        }
    }
}

struct ConnectionStartPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: 1,
                y: reduceMotion || !configuration.isPressed ? 1 : 0.94
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion
                    ? .linear(duration: PosterMotion.reduced)
                    : PosterMotion.press,
                value: configuration.isPressed
            )
    }
}

#Preview("Invite") {
    ConnectionView(model: PreviewFixtures.model(phase: .connection))
}

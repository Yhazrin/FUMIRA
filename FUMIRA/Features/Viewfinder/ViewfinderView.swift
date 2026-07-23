import SwiftUI

struct ViewfinderView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsAreReady = false

    var body: some View {
        ZStack {
            preview
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    PosterEffects.cameraTopScrim,
                    Color.clear,
                    PosterEffects.cameraBottomScrim
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: PosterSpacing.md) {
                PosterTitleView(
                    segments: ["把现在", "拍下来"],
                    color: PosterPalette.paperWhite,
                    fontSize: PosterTypography.immersiveCameraTitleSize
                )
                .shadow(
                    color: PosterEffects.cameraTitleShadow,
                    radius: PosterEffects.cameraTitleShadowRadius,
                    y: PosterEffects.cameraTitleShadowOffset
                )

                HStack(spacing: PosterSpacing.sm) {
                    StatusPill(
                        icon: model.isUsingLiveCamera ? "camera.fill" : "iphone",
                        label: model.isUsingLiveCamera ? "实时相机" : "模拟器场景",
                        isActive: true
                    )
                    if let snapshot = model.hardwareSnapshot {
                        StatusPill(icon: "battery.75", label: "\(snapshot.batteryLevel)%")
                    }
                }

                Spacer()

                VStack(spacing: PosterSpacing.sm) {
                    TimeRail(value: model.selectedTime.normalized) { normalized in
                        model.updateTime(normalized: normalized)
                    }

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                            Text("从这一刻出发")
                                .font(.headline)
                                .foregroundStyle(PosterPalette.ink)
                            Text("先拍原图，再由 AI 理解并写下时间故事")
                                .font(.caption)
                                .foregroundStyle(PosterPalette.mutedInk)
                        }

                        Spacer()

                        ShutterButton {
                            Task { await model.capture() }
                        }
                    }
                }
                .padding(PosterSpacing.md)
                .background(PosterEffects.cameraControlSurface)
                .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
                .shadow(color: PosterEffects.floating, radius: 16, y: 8)
                .allowsHitTesting(controlsAreReady)
            }
            .padding(.horizontal, PosterSpacing.lg)
            .padding(.top, PosterSpacing.md)
            .padding(.bottom, PosterSpacing.lg)
        }
        .accessibilityElement(children: .contain)
        .task {
            try? await Task.sleep(for: PosterMotion.cameraInputGuard)
            guard !Task.isCancelled else { return }
            controlsAreReady = true
        }
    }

    @ViewBuilder
    private var preview: some View {
        if reduceMotion {
            model.cameraPreview
        } else {
            model.cameraPreview
                .matchedGeometryEffect(id: "camera-photo", in: namespace)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            ViewfinderView(model: PreviewFixtures.model(phase: .viewfinder), namespace: namespace)
        }
    }
    return PreviewWrapper()
}

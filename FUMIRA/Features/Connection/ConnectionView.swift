import SwiftUI

struct ConnectionView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heroMoment: PosterHeroMoment = .invite
    @State private var didEnter = false

    var body: some View {
        ZStack {
            posterBackdrop

            VStack(spacing: 0) {
                Spacer(minLength: PosterSpacing.xl)

                PosterKeywordHero(moment: heroMoment, fontSize: 46)
                    .padding(.horizontal, PosterSpacing.lg)
                    .animation(
                        reduceMotion
                            ? .linear(duration: PosterMotion.reduced)
                            : .spring(response: PosterMotion.poster, dampingFraction: 0.86),
                        value: heroMoment
                    )

                Text(inviteCopy)
                    .font(.subheadline)
                    .foregroundStyle(PosterPalette.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PosterSpacing.xl)
                    .padding(.top, PosterSpacing.md)

                Spacer(minLength: PosterSpacing.lg)

                // Mid-ground park vignette — scene is the visual hero, not a device mock.
                TemporalParkScene(time: .now, cornerRadius: PosterRadius.card)
                    .frame(height: 200)
                    .padding(.horizontal, PosterSpacing.xl)
                    .shadow(color: PosterEffects.floating, radius: 18, y: 10)
                    .accessibilityHidden(true)

                Spacer(minLength: PosterSpacing.lg)

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: "连接 FutureCam",
                        accessibilityHint: "通过蓝牙连接实体时间旋钮"
                    ) {
                        model.beginHardwarePath()
                    }

                    PosterCapsuleButton(
                        title: "仅用手机体验",
                        style: .secondary,
                        accessibilityHint: "跳过硬件，直接进入手机拍摄流程"
                    ) {
                        model.beginPhoneOnlyPath()
                    }
                }
                .padding(.horizontal, PosterSpacing.lg)
                .padding(.bottom, PosterSpacing.xl)
            }
        }
        .onAppear {
            guard !didEnter else { return }
            didEnter = true
            // Soft composition shift: invite → connecting-like rearrange → settle invite.
            // No continuous bobbing; Reduce Motion stays on invite.
            guard !reduceMotion else { return }
            heroMoment = .invite
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(520))
                withAnimation(.spring(response: PosterMotion.poster, dampingFraction: 0.86)) {
                    heroMoment = .connecting
                }
                try? await Task.sleep(for: .milliseconds(720))
                withAnimation(.spring(response: PosterMotion.poster, dampingFraction: 0.86)) {
                    heroMoment = .invite
                }
            }
        }
    }

    private var inviteCopy: String {
        switch heroMoment {
        case .connecting:
            "把此刻，留给未来"
        default:
            "给时间，一张照片"
        }
    }

    private var posterBackdrop: some View {
        ZStack {
            // Direction H: sky as large upper field, paper mid, grass/pine lower planes.
            PosterPalette.sky.ignoresSafeArea()

            LinearGradient(
                colors: [
                    PosterPalette.sky,
                    PosterPalette.skySoft,
                    PosterPalette.paper,
                    PosterPalette.grassLight.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Layered grass planes — flat poster blocks, not AI gradients.
            VStack(spacing: 0) {
                Spacer()
                Ellipse()
                    .fill(PosterPalette.grassLight.opacity(0.65))
                    .frame(height: 240)
                    .offset(y: 70)
                Ellipse()
                    .fill(PosterPalette.pine.opacity(0.42))
                    .frame(height: 170)
                    .offset(y: 50)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

#Preview("Invite") {
    ConnectionView(model: PreviewFixtures.model(phase: .connection))
}

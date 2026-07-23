import SwiftUI

struct ConnectionView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didEnter = false
    @State private var heroVisible = false
    @State private var bodyVisible = false
    @State private var ctaVisible = false
    @State private var entranceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            ParkPosterBackdrop(motionField: model.motionField)

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: max(118, proxy.size.height * 0.2))

                    PosterKeywordHero(moment: .invite, fontSize: 43)
                        .frame(maxWidth: 330, alignment: .leading)
                        .padding(.horizontal, PosterSpacing.xl)
                        .flatMotionEntrance(isVisible: heroVisible, reduceMotion: reduceMotion)

                    VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                        Text("连接 FutureCam")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(PosterPalette.ink)
                        Text("或先用手机，给此刻选一个年份。")
                            .font(.subheadline)
                            .foregroundStyle(PosterPalette.pine.opacity(0.78))
                    }
                    .padding(.horizontal, PosterSpacing.xl)
                    .padding(.top, PosterSpacing.lg)
                    .flatMotionEntrance(
                        isVisible: bodyVisible,
                        reduceMotion: reduceMotion,
                        delay: .milliseconds(80)
                    )

                    Spacer(minLength: PosterSpacing.lg)

                    VStack(alignment: .leading, spacing: PosterSpacing.md) {
                        ConnectionStartButton {
                            model.beginPhoneOnlyPath()
                        }

                        ConnectionHardwareLink {
                            model.beginHardwarePath()
                        }
                    }
                    .padding(.horizontal, PosterSpacing.lg)
                    .padding(.bottom, PosterSpacing.xl)
                    .flatMotionEntrance(
                        isVisible: ctaVisible,
                        reduceMotion: reduceMotion,
                        delay: .milliseconds(140)
                    )
                }
            }
        }
        .onAppear {
            playEntranceIfNeeded()
        }
        .onDisappear {
            entranceTask?.cancel()
            entranceTask = nil
        }
    }

    private func playEntranceIfNeeded() {
        guard !didEnter else { return }
        didEnter = true
        if reduceMotion {
            heroVisible = true
            bodyVisible = true
            ctaVisible = true
            return
        }
        entranceTask?.cancel()
        entranceTask = Task { @MainActor in
            withAnimation(PosterMotion.decelerate) {
                heroVisible = true
            }
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            withAnimation(PosterMotion.decelerate) {
                bodyVisible = true
            }
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            withAnimation(PosterMotion.decelerate) {
                ctaVisible = true
            }
        }
    }

}

/// An organic, poster-native launch control. It borrows the direct visual
/// response principle from ShipSwift's full-screen controls, but stays flat and
/// avoids generic capsules, heavy shadows, and dark outlines.
private struct ConnectionStartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PosterSpacing.md) {
                ZStack {
                    Circle()
                        .fill(PosterPalette.paperWhite.opacity(0.9))
                        .frame(width: 42, height: 42)
                    Image(systemName: "camera.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(PosterPalette.pine)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("用手机拍一张")
                        .font(.title3.weight(.bold))
                    Text("从此刻，拨到任意一年")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PosterPalette.paperWhite.opacity(0.76))
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .padding(10)
                    .background(Circle().fill(PosterPalette.leafGreen))
            }
            .padding(.horizontal, PosterSpacing.md)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 17,
                    bottomTrailingRadius: 30,
                    topTrailingRadius: 20,
                    style: .continuous
                )
                .fill(PosterPalette.pine)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(PosterPalette.leafGreen.opacity(0.78))
                        .frame(width: 54, height: 54)
                        .offset(x: 12, y: -16)
                }
                .overlay(alignment: .bottomLeading) {
                    Capsule()
                        .fill(PosterPalette.sky.opacity(0.52))
                        .frame(width: 76, height: 8)
                        .rotationEffect(.degrees(-8))
                        .offset(x: 32, y: 16)
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 17,
                    bottomTrailingRadius: 30,
                    topTrailingRadius: 20,
                    style: .continuous
                ))
            }
        }
        .buttonStyle(ConnectionOrganicPressStyle())
        .accessibilityLabel("用手机拍一张")
        .accessibilityHint("跳过硬件，直接进入手机拍摄流程")
    }
}

private struct ConnectionHardwareLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PosterSpacing.sm) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PosterPalette.skyDeep)
                Text("已有 FutureCam？连接实体相机")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PosterPalette.pine)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PosterPalette.leafGreen)
            }
            .padding(.horizontal, PosterSpacing.sm)
            .frame(minHeight: 42)
        }
        .buttonStyle(ConnectionOrganicPressStyle())
        .accessibilityLabel("连接 FutureCam")
        .accessibilityHint("通过蓝牙连接实体时间旋钮")
    }
}

private struct ConnectionOrganicPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Preserve width: a firm vertical compression reads as a physical press.
            .scaleEffect(x: 1, y: reduceMotion || !configuration.isPressed ? 1 : 0.94, anchor: .center)
            .offset(y: reduceMotion || !configuration.isPressed ? 0 : 2)
            .saturation(reduceMotion || !configuration.isPressed ? 1 : 1.12)
            .animation(reduceMotion ? .linear(duration: PosterMotion.reduced) : PosterMotion.press, value: configuration.isPressed)
    }
}

#Preview("Invite") {
    ConnectionView(model: PreviewFixtures.model(phase: .connection))
}

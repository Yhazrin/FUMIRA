import SwiftUI

struct ConnectionView: View {
    let model: AppModel
    var entryProgress: CGFloat = 0
    let onLaunchCamera: () -> Void

    init(
        model: AppModel,
        entryProgress: CGFloat = 0,
        onLaunchCamera: @escaping () -> Void = {}
    ) {
        self.model = model
        self.entryProgress = entryProgress
        self.onLaunchCamera = onLaunchCamera
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Clay 背景 — 奶油底 + 颗粒
                ClayAppBackground()
                    .ignoresSafeArea()

                FUMIRAWordmark()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, ClaySpacing.xxl)
                    .padding(
                        .top,
                        proxy.safeAreaInsets.top + ClaySpacing.xxxl + 28
                    )
                    .opacity(1 - FUMIRASpatialMotion.map(entryProgress, from: 0.18...0.62, to: 0...1))
                    .scaleEffect(1 - FUMIRASpatialMotion.map(entryProgress, from: 0...0.62, to: 0...0.035), anchor: .topLeading)

                if entryProgress <= 0.001 {
                    CameraInvitePanel(onLaunchCamera: onLaunchCamera)
                        .position(
                            x: proxy.size.width * 0.5,
                            y: proxy.size.height * 0.46
                        )
                        .transition(.identity)
                }
            }
        }
    }
}

/// The invite is a small constructed scene, not a lone floating control: a
/// loose cluster of small clay motifs orbits the shutter — echoing the
/// mood-board's scatter of floating objects around a hero device — while a
/// one-line prompt and a quiet ±100y strip keep the actual task legible.
private struct CameraInvitePanel: View {
    let onLaunchCamera: () -> Void

    var body: some View {
        ZStack {
            constellation

            VStack(spacing: ClaySpacing.lg) {
                Text("给这一刻拍张照片\n看看时间会怎么讲它")
                    .font(ClayTypography.bodySmall)
                    .foregroundStyle(ClayPalette.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .accessibilityHidden(true)

                CameraLaunchClayButton(action: onLaunchCamera)

                timeStrip
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var constellation: some View {
        ZStack {
            satelliteTile(
                systemImage: "aperture",
                base: ClayPalette.timeBlue,
                rim: ClayPalette.timeBlueRim,
                size: 34,
                cornerRadius: ClayShape.pill
            )
            .rotationEffect(.degrees(-8))
            .offset(x: -116, y: -100)

            satelliteTile(
                systemImage: "sparkles",
                base: ClayPalette.yellow,
                rim: ClayPalette.yellowRim,
                size: 30,
                cornerRadius: ClayShape.sm
            )
            .rotationEffect(.degrees(10))
            .offset(x: 114, y: -108)

            satelliteTile(
                systemImage: "photo",
                base: ClayPalette.parkGreen,
                rim: ClayPalette.parkGreenRim,
                size: 36,
                cornerRadius: ClayShape.sm
            )
            .rotationEffect(.degrees(6))
            .offset(x: -126, y: 44)

            satelliteTile(
                systemImage: "arrow.triangle.2.circlepath",
                base: ClayPalette.orange,
                rim: ClayPalette.orangeRim,
                size: 30,
                cornerRadius: ClayShape.pill
            )
            .rotationEffect(.degrees(-11))
            .offset(x: 120, y: 54)

            miniBead(ClayPalette.lime)
                .offset(x: -38, y: -122)
            miniBead(ClayPalette.timeBlue)
                .offset(x: 50, y: 118)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func satelliteTile(
        systemImage: String,
        base: Color,
        rim: Color,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        ZStack {
            ClaySurface(
                base: base,
                rim: rim,
                cornerRadius: cornerRadius,
                shadow: ClayShadow.small,
                layeredShadow: nil
            )
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(ClayPalette.warmWhite)
        }
        .frame(width: size, height: size)
    }

    private func miniBead(_ base: Color) -> some View {
        Circle()
            .fill(base)
            .frame(width: 12, height: 12)
            .clayShadow(ClayShadow.seatedSmall)
    }

    private var timeStrip: some View {
        HStack(spacing: ClaySpacing.sm) {
            timeMark("-100y", emphasized: false)
            timeRule
            timeMark("NOW", emphasized: true)
            timeRule
            timeMark("+100y", emphasized: false)
        }
        .accessibilityHidden(true)
    }

    private var timeRule: some View {
        Capsule()
            .fill(ClayPalette.textMuted.opacity(0.22))
            .frame(width: 14, height: 2)
    }

    private func timeMark(_ label: String, emphasized: Bool) -> some View {
        Text(label)
            .font(ClayTypography.monoTiny)
            .foregroundStyle(emphasized ? ClayPalette.orange : ClayPalette.textMuted.opacity(0.6))
    }
}

private struct FUMIRAWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ClaySpacing.xs) {
            Text("FUMIRA")
                .font(ClayTypography.displayLarge)
                .foregroundStyle(ClayPalette.textPrimary)
                .tracking(1.2)

            HStack(spacing: ClaySpacing.sm) {
                Capsule()
                    .fill(ClayPalette.orange)
                    .frame(width: 36, height: 5)
                    .clayShadow(ClayShadow.seatedSmall)

                Text("TIME CAMERA")
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FUMIRA 时间相机")
    }
}

/// A clay shutter seated on the cream ground: matte body, one lit chamfer,
/// and a pair of toy indicator beads that give the object a face.
private struct CameraLaunchClayButton: View {
    let action: () -> Void

    var body: some View {
        ZStack {
            ClaySurface(
                base: ClayPalette.warmWhite,
                rim: ClayPalette.warmWhiteRim,
                cornerRadius: ClayShape.pill,
                shadow: ClayShadow.buttonRest,
                layeredShadow: nil
            )
            .frame(width: 132, height: 132)

            Button(action: action) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 29, weight: .bold))
                    .frame(width: 84, height: 84)
            }
            .clayButtonStyle(
                base: ClayPalette.orange,
                rim: ClayPalette.orangeDepth,
                foreground: ClayPalette.warmWhite,
                cornerRadius: ClayShape.pill,
                depth: 5
            )
            .contentShape(Circle())

            indicatorBeads
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("进入时间相机")
        .accessibilityHint("打开相机，拍下一张给时间的照片")
    }

    private var indicatorBeads: some View {
        HStack(spacing: ClaySpacing.xs) {
            bead(ClayPalette.lime, rim: ClayPalette.limeRim)
            bead(ClayPalette.yellow, rim: ClayPalette.yellowRim)
        }
        .offset(y: 82)
        .accessibilityHidden(true)
    }

    private func bead(_ base: Color, rim: Color) -> some View {
        Circle()
            .fill(base)
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: ClayFacet.bandStops,
                            startPoint: ClayFacet.bandStart,
                            endPoint: ClayFacet.bandEnd
                        ),
                        lineWidth: ClayFacet.bandWidth
                    )
            }
            .frame(width: 10, height: 10)
            .background {
                Circle()
                    .fill(rim)
                    .offset(y: 2)
            }
            .clayShadow(ClayShadow.seatedSmall)
    }
}

#Preview("Invite") {
    ConnectionView(
        model: PreviewFixtures.model(phase: .connection)
    )
}

import SwiftUI

/// Preview gallery for the Clay OS design system components.
struct ClayStylePreview: View {
    @State private var progress: Double = 0.42
    @State private var isBuilding = false
    @State private var selectedSegment = 0
    @State private var timeValue: Double = 0

    var body: some View {
        ZStack {
            ClayAppBackground()

            ScrollView {
                VStack(spacing: ClaySpacing.sectionGap) {
                    header
                    terminalPanel
                    actionGrid
                    progressPanel
                    segmentSection
                    chipSection
                    dialSection
                }
                .padding(.horizontal, ClaySpacing.screenEdgeMargin)
                .padding(.vertical, ClaySpacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: ClaySpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("FUMIRA CLAY OS")
                    .font(ClayTypography.displaySmall)
                    .foregroundStyle(ClayPalette.textOnDark)

                Text("DESIGN SYSTEM PREVIEW")
                    .font(ClayTypography.monoSmall)
                    .tracking(ClayTypography.trackingWide)
                    .foregroundStyle(ClayPalette.textOnDark.opacity(0.55))
            }

            Spacer()

            HStack(spacing: 7) {
                ClayIndicator(ClayPalette.orange)
                ClayIndicator(ClayPalette.lime)
                ClayIndicator(ClayPalette.yellow)
            }
        }
    }

    private var terminalPanel: some View {
        ClayTerminal("SYSTEM") {
            VStack(alignment: .leading, spacing: ClaySpacing.stackDefault) {
                HStack {
                    Text("01")
                        .font(ClayTypography.monoLarge)
                        .foregroundStyle(ClayPalette.orange)

                    Capsule()
                        .fill(ClayPalette.orange)
                        .frame(width: 56, height: 9)

                    Capsule()
                        .fill(ClayPalette.lime)
                        .frame(width: 25, height: 9)

                    Spacer()
                }

                HStack(spacing: ClaySpacing.lg) {
                    ClayTerminalScreen {
                        VStack(alignment: .leading, spacing: 14) {
                            Capsule()
                                .fill(ClayPalette.orange)
                                .frame(width: 48, height: 7)

                            HStack(spacing: 7) {
                                Text(">")
                                    .foregroundStyle(ClayPalette.orange)
                                Text("MiMo")
                                    .foregroundStyle(ClayPalette.lime)
                            }
                            .font(.system(size: 27, weight: .black, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(width: 156, height: 116)

                    VStack(spacing: 9) {
                        ForEach(0..<5, id: \.self) { index in
                            Capsule()
                                .fill(ClayPalette.warmWhite.opacity(0.44))
                                .frame(width: 54 - CGFloat(index % 2) * 10, height: 6)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var actionGrid: some View {
        VStack(spacing: ClaySpacing.stackDefault) {
            Button {
                withAnimation(ClayMotion.toggleSpring) {
                    isBuilding.toggle()
                    progress = isBuilding ? 0.82 : 0.42
                }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: isBuilding ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .black))
                    Text(isBuilding ? "BUILDING SCENE" : "BUILD SCENE")
                        .font(ClayTypography.label)
                        .tracking(ClayTypography.trackingTight)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .black))
                }
                .padding(.horizontal, ClaySpacing.buttonHorizontal)
                .frame(height: 66)
            }
            .clayButtonStyle(
                base: ClayPalette.orange,
                rim: ClayPalette.orangeRim
            )

            HStack(spacing: ClaySpacing.stackDefault) {
                Button { } label: {
                    Label("SEASON", systemImage: "leaf.fill")
                        .font(ClayTypography.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                }
                .clayButtonStyle(
                    base: ClayPalette.lime,
                    rim: ClayPalette.limeRim
                )

                Button { } label: {
                    Label("TIME", systemImage: "clock.fill")
                        .font(ClayTypography.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                }
                .clayButtonStyle(
                    base: ClayPalette.yellow,
                    rim: ClayPalette.yellowRim
                )
            }
        }
    }

    private var progressPanel: some View {
        ClayPanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("MODEL STATUS")
                        .font(ClayTypography.monoTiny)
                        .tracking(ClayTypography.trackingWide)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(ClayTypography.subheading)
                }
                .foregroundStyle(ClayPalette.textPrimary)

                ClayProgress(progress: progress)

                HStack(spacing: 10) {
                    ClayChip("SCAN", isActive: true)
                    ClayChip("FORM", isActive: progress > 0.35)
                    ClayChip("CLAY", isActive: progress > 0.65)
                }
            }
        }
    }

    private var segmentSection: some View {
        ClaySegmentedControl(
            options: ["PAST", "NOW", "FUTURE"],
            selectedIndex: $selectedSegment
        )
    }

    private var chipSection: some View {
        ClayPanel {
            VStack(alignment: .leading, spacing: ClaySpacing.stackDefault) {
                Text("STATUS CHIPS")
                    .font(ClayTypography.monoSmall)
                    .foregroundStyle(ClayPalette.textMuted)

                HStack(spacing: ClaySpacing.sm) {
                    ClayChip("IDLE")
                    ClayChip("ACTIVE", isActive: true, activeColor: ClayPalette.orange)
                    ClayChip("DONE", isActive: true, activeColor: ClayPalette.lime)
                    ClayChip("WAIT", isActive: true, activeColor: ClayPalette.yellow)
                }
            }
        }
    }

    private var dialSection: some View {
        ClayPanel {
            ClayTimeDial(value: $timeValue)
        }
    }
}

#Preview("Clay OS Preview") {
    ClayStylePreview()
}

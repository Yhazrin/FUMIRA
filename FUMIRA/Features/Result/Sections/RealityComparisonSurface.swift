import SwiftUI
import UIKit

/// Inline original ↔ generated comparison on the hero photo frame.
/// Presented by sliding the result panel down — never as a separate page.
struct RealityComparisonSurface: View {
    let original: UIImage?
    let generated: UIImage?
    let target: TimePosition
    let close: () -> Void

    @State private var position: CGFloat = 0.5
    @State private var showsGrid = true
    @State private var comparisonMode = RealityComparisonMode.auditInitial

    var body: some View {
        GeometryReader { proxy in
            let boundary = proxy.size.width * min(max(position, 0), 1)

            ZStack(alignment: .topLeading) {
                if comparisonMode == .split {
                    splitComparison(
                        size: proxy.size,
                        boundary: boundary
                    )
                } else {
                    TemporalBlinkComparator(
                        originalImage: original,
                        generatedImage: generated,
                        targetTime: target
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }

                comparisonChrome
            }
            // Both comparison modes replace pixels in one exact crop. Parent
            // phase animations must never turn the switch into a crossfade.
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
            .clipShape(
                RoundedRectangle(cornerRadius: ClayShape.lg, style: .continuous)
            )
        }
    }

    private func splitComparison(
        size: CGSize,
        boundary: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            comparisonImage(original)
                .frame(width: size.width, height: size.height)
                .clipped()

            if showsGrid {
                RealityComparisonGrid()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            comparisonImage(generated)
                .frame(width: size.width, height: size.height)
                .mask {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: boundary)
                        Rectangle()
                            .fill(Color.white)
                    }
                }
                .allowsHitTesting(false)

            boundaryHandle(at: boundary, height: size.height)
                .allowsHitTesting(false)

            HStack {
                Text("原片 · NOW")
                    .foregroundStyle(ClayPalette.orangeRim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ClayPalette.warmWhite.opacity(0.94), in: Capsule())
                Spacer()
                Text(target.compactLabel)
                    .foregroundStyle(ClayPalette.warmWhite)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ClayPalette.orange, in: Capsule())
            }
            .font(ClayTypography.labelSmall.weight(.semibold))
            .padding(.horizontal, ClaySpacing.lg)
            .padding(.top, ClaySpacing.xxl + CameraChromeMetrics.controlDiameter)
            .allowsHitTesting(false)
            .zIndex(4)

            PosterGlassCard(cornerRadius: ClayShape.card) {
                Text("拖动，看时间差")
                    .font(ClayTypography.heading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ClaySpacing.lg)
            .padding(.bottom, ClaySpacing.lg)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            .zIndex(4)

            Color.clear
                .contentShape(Rectangle())
                .gesture(boundaryGesture(width: size.width))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("result.reality-boundary")
                .accessibilityLabel("现实与目标时间边界")
                .accessibilityValue("原片占 \(Int(position * 100))%")
                .accessibilityHint("左右拖动比较原片与目标时间；上下滑动可逐级调整")
                .accessibilityAdjustableAction(adjustBoundary)
                .zIndex(3)
        }
    }

    private var comparisonChrome: some View {
        HStack(spacing: ClaySpacing.sm) {
            Spacer(minLength: 0)

            comparisonControl(
                systemImage: comparisonMode == .split
                    ? "circle.lefthalf.filled"
                    : "arrow.left.and.right",
                accessibilityLabel: comparisonMode == .split
                    ? "切换到眨眼对照"
                    : "切换到拖动对照",
                identifier: "result.comparison-mode"
            ) {
                comparisonMode = comparisonMode == .split ? .blink : .split
            }

            if comparisonMode == .split {
                comparisonControl(
                    systemImage: showsGrid ? "grid" : "grid.circle",
                    accessibilityLabel: showsGrid ? "隐藏对照栅格" : "显示对照栅格",
                    identifier: "result.comparison-grid"
                ) {
                    showsGrid.toggle()
                }
            }

            comparisonControl(
                systemImage: "xmark",
                accessibilityLabel: "关闭现实对照",
                identifier: "result.comparison-close",
                action: close
            )
        }
        .padding(.horizontal, ClaySpacing.lg)
        .padding(.top, ClaySpacing.sm)
        .zIndex(5)
    }

    private func comparisonControl(
        systemImage: String,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(ClayTypography.label)
                .foregroundStyle(ClayPalette.orangeRim)
                .frame(
                    width: CameraChromeMetrics.controlDiameter,
                    height: CameraChromeMetrics.controlDiameter
                )
                .background(ClayPalette.warmWhite.opacity(0.94), in: Circle())
                .overlay {
                    Circle()
                        .stroke(ClayPalette.orange.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(accessibilityLabel)
    }

    private func boundaryHandle(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(ClayPalette.warmWhite.opacity(0.92))
                .frame(width: 3, height: height)
                .shadow(color: ClayPalette.orange.opacity(0.22), radius: 6)

            Capsule(style: .continuous)
                .fill(ClayPalette.warmWhite)
                .frame(width: 34, height: 56)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(ClayPalette.orange.opacity(0.28), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(ClayTypography.labelSmall)
                        .foregroundStyle(ClayPalette.orangeRim)
                }
                .shadow(color: ClayPalette.orange.opacity(0.18), radius: 10, y: 3)
        }
        .position(x: x, y: height * 0.5)
    }

    private func boundaryGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                position = min(max(value.location.x / max(width, 1), 0), 1)
            }
    }

    private func adjustBoundary(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            position = min(position + 0.1, 1)
        case .decrement:
            position = max(position - 0.1, 0)
        @unknown default:
            break
        }
    }

    @ViewBuilder
    private func comparisonImage(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ClayPalette.orangeRim
        }
    }
}

private enum RealityComparisonMode: Equatable {
    case split
    case blink

    static var auditInitial: Self {
        #if DEBUG
        ProcessInfo.processInfo.environment["FUMIRA_AUDIT_COMPARISON_MODE"] == "blink"
            ? .blink
            : .split
        #else
        .split
        #endif
    }
}

/// Rule-of-thirds grid for still original ↔ generated comparison.
private struct RealityComparisonGrid: View {
    var body: some View {
        Canvas { context, size in
            let color = ClayPalette.warmWhite.opacity(0.38)
            let thirdsX = [size.width / 3, size.width * 2 / 3]
            let thirdsY = [size.height / 3, size.height * 2 / 3]
            for x in thirdsX {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
            for y in thirdsY {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
    }
}

enum RealityAlignmentGeometry {
    static func progress(
        currentRoll: Double,
        currentPitch: Double,
        currentYaw: Double,
        captured: CaptureMotionSample
    ) -> CGFloat {
        let roll = angularDistance(currentRoll, captured.roll)
        let pitch = angularDistance(currentPitch, captured.pitch)
        let yaw = angularDistance(currentYaw, captured.yaw)
        let weightedDistance = sqrt(
            roll * roll
                + pitch * pitch
                + yaw * yaw * 0.45
        )
        return CGFloat(min(max(1 - weightedDistance / 0.24, 0), 1))
    }

    static func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        var angle = lhs - rhs
        while angle > .pi { angle -= .pi * 2 }
        while angle < -.pi { angle += .pi * 2 }
        return abs(angle)
    }
}

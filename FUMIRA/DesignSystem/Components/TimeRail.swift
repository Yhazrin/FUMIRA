import SwiftUI

struct TimeRail: View {
    let value: Double
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragValue: Double?
    @State private var isDragging = false

    private let horizontalInset: CGFloat = 22

    private let landmarks: [(label: String, normalized: Double)] = [
        ("-100", -1),
        ("-30", TimePosition(offsetDays: -30 * 365.25).normalized),
        ("NOW", 0),
        ("+30", TimePosition(offsetDays: 30 * 365.25).normalized),
        ("+100", 1)
    ]

    private var displayValue: Double {
        dragValue ?? value
    }

    private var timePosition: TimePosition {
        TimePosition(normalized: displayValue)
    }

    var body: some View {
        VStack(spacing: PosterSpacing.md) {
            Text(timePosition.compactLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PosterPalette.ink)
                .contentTransition(.numericText())
                .animation(isDragging || reduceMotion ? nil : PosterMotion.flow, value: displayValue)

            GeometryReader { proxy in
                let width = proxy.size.width
                let thumbX = normalizedToX(displayValue, width: width)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PosterPalette.ink)
                        .frame(height: 4)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.horizontal, horizontalInset)

                    ForEach(Array(landmarks.enumerated()), id: \.offset) { _, landmark in
                        let x = normalizedToX(landmark.normalized, width: width)
                        VStack(spacing: PosterSpacing.xs) {
                            Circle()
                                .fill(landmark.normalized == 0 ? PosterPalette.energyLime : PosterPalette.paperWhite)
                                .frame(width: landmark.normalized == 0 ? 14 : 10, height: landmark.normalized == 0 ? 14 : 10)
                                .overlay {
                                    Circle()
                                        .stroke(PosterPalette.ink, lineWidth: 1.5)
                                }
                            Text(landmark.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(PosterPalette.mutedInk)
                        }
                        .position(x: x, y: proxy.size.height * 0.72)
                        .allowsHitTesting(false)
                    }

                    Capsule()
                        .fill(PosterPalette.energyLime)
                        .frame(width: max(4, thumbX - horizontalInset), height: 4)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .offset(x: horizontalInset)

                    Capsule()
                        .fill(PosterPalette.energyLime)
                        .frame(width: 36, height: 22)
                        .overlay {
                            Capsule()
                                .stroke(PosterPalette.ink, lineWidth: 2)
                        }
                        .position(x: thumbX, y: proxy.size.height * 0.38)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            let normalized = xToNormalized(gesture.location.x, width: width)
                            dragValue = normalized
                            onChange(normalized)
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragValue = nil
                        }
                )
            }
            .frame(height: 72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间轴")
        .accessibilityValue(timePosition.compactLabel)
        .accessibilityHint("左右拖动浏览过去与未来，或使用调高减低手势微调")
        .accessibilityAdjustableAction { direction in
            let step = accessibilityStep(for: value)
            let delta = direction == .increment ? step : -step
            let next = min(max(value + delta, -1), 1)
            onChange(next)
        }
    }

    private func normalizedToX(_ normalized: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(normalized, -1), 1)
        let usableWidth = max(1, width - horizontalInset * 2)
        return horizontalInset + (clamped + 1) / 2 * usableWidth
    }

    private func xToNormalized(_ x: CGFloat, width: CGFloat) -> Double {
        let usableWidth = max(1, width - horizontalInset * 2)
        let clamped = min(max((x - horizontalInset) / usableWidth, 0), 1)
        return Double(clamped * 2 - 1)
    }

    private func accessibilityStep(for normalized: Double) -> Double {
        let magnitude = abs(normalized)
        if magnitude < 0.15 { return 0.008 }
        if magnitude < 0.5 { return 0.03 }
        return 0.08
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var value = 0.0

        var body: some View {
            TimeRail(value: value) { value = $0 }
                .padding()
        }
    }
    return PreviewWrapper()
}

import SwiftUI

/// Audio-waveform continuous time scrubber for ±100 years.
/// Horizontal position maps linearly to `TimePosition.normalized`; day mapping
/// stays nonlinear via `TimePosition` (finer near NOW).
enum WaveTimeRailChrome {
    /// Paper / light surfaces — ink bars.
    case paper
    /// Camera bottom scrim — light bars over dark gradient.
    case immersive
}

struct WaveTimeRail: View {
    let value: Double
    var chrome: WaveTimeRailChrome = .paper
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragValue: Double?
    @State private var isDragging = false
    @State private var hapticBucket = 0

    private let horizontalInset: CGFloat = 16
    private let barMaxHeight: CGFloat = 40
    private let barMinHeight: CGFloat = 8
    private let railHeight: CGFloat = 88

    private var idleBarColor: Color {
        switch chrome {
        case .paper: PosterPalette.waveIdle
        case .immersive: PosterPalette.paperWhite.opacity(0.38)
        }
    }

    private var landmarkColor: Color {
        switch chrome {
        case .paper: PosterPalette.mutedInk
        case .immersive: PosterPalette.paperWhite.opacity(0.7)
        }
    }

    private var landmarkNowColor: Color {
        switch chrome {
        case .paper: PosterPalette.ink
        case .immersive: PosterPalette.paperWhite
        }
    }

    private var yearLabelForeground: Color {
        switch chrome {
        case .paper: PosterPalette.ink
        case .immersive: PosterPalette.paperWhite
        }
    }

    private var yearLabelFill: Color {
        switch chrome {
        case .paper: PosterPalette.paperWhite.opacity(0.92)
        case .immersive: PosterPalette.ink.opacity(0.55)
        }
    }

    /// Deterministic waveform: densest / most distinctive rhythm near NOW (center).
    private static let barHeights: [CGFloat] = {
        let count = 33
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            let centered = (t - 0.5) * 2
            let envelope = 0.42 + 0.58 * exp(-pow(centered * 1.65, 2))
            let frequency = 2.4 + 9.0 * (1 - abs(centered))
            let phase = Double(index) * 0.55 + centered * .pi
            let wave = 0.28 + 0.72 * abs(sin(centered * .pi * frequency + phase))
            let accent = abs(centered) < 0.1 ? 0.12 : 0
            return CGFloat(min(1, envelope * wave + accent))
        }
    }()

    private var barCount: Int { Self.barHeights.count }

    private var displayValue: Double {
        dragValue ?? value
    }

    private var timePosition: TimePosition {
        TimePosition(normalized: displayValue)
    }

    private var yearLabel: String {
        let year = Calendar.current.component(.year, from: timePosition.targetDate())
        return "\(year)"
    }

    private var selectedBarIndex: Int {
        let t = (min(max(displayValue, -1), 1) + 1) / 2
        return Int((t * Double(barCount - 1)).rounded())
    }

    var body: some View {
        VStack(spacing: PosterSpacing.sm) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let thumbX = normalizedToX(displayValue, width: width)

                ZStack(alignment: .bottom) {
                    waveBars(width: width)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    cursor(at: thumbX, height: proxy.size.height)
                        .allowsHitTesting(false)

                    sparseScale(width: width, height: proxy.size.height)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width))
            }
            .frame(height: railHeight)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间轴")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("左右拖动浏览过去与未来，或使用调高减低手势微调")
        .accessibilityAdjustableAction { direction in
            let step = accessibilityStep(for: value)
            let delta = direction == .increment ? step : -step
            let next = WaveTimeBrowseSnap.snap(
                TimePosition(normalized: min(max(value + delta, -1), 1))
            )
            onChange(next.normalized)
        }
        .sensoryFeedback(.selection, trigger: hapticBucket)
    }

    private var accessibilityValueText: String {
        if abs(timePosition.offsetDays) < 0.5 {
            return "现在，\(yearLabel) 年"
        }
        let direction = timePosition.offsetDays < 0 ? "向过去" : "向未来"
        return "\(timePosition.compactLabel)，目标 \(yearLabel) 年，\(direction)"
    }

    private func waveBars(width: CGFloat) -> some View {
        let usable = max(1, width - horizontalInset * 2)
        let spacing = usable / CGFloat(barCount)
        let barWidth = max(2.5, spacing * 0.42)

        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<barCount, id: \.self) { index in
                let relative = Self.barHeights[index]
                let height = barMinHeight + (barMaxHeight - barMinHeight) * relative
                let isSelected = index == selectedBarIndex

                RoundedRectangle(cornerRadius: PosterRadius.waveBar, style: .continuous)
                    .fill(isSelected ? PosterPalette.moss : idleBarColor)
                    .frame(width: barWidth, height: height)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .animation(
                        isDragging || reduceMotion ? nil : PosterMotion.flow,
                        value: selectedBarIndex
                    )
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 22)
    }

    private func cursor(at x: CGFloat, height: CGFloat) -> some View {
        let cursorHeight = barMaxHeight + 10

        return ZStack {
            Capsule()
                .fill(PosterPalette.moss)
                .frame(width: 3, height: cursorHeight)
                .position(x: x, y: height - 22 - cursorHeight / 2)

            Text(yearLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(yearLabelForeground)
                .padding(.horizontal, PosterSpacing.sm)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(yearLabelFill)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(PosterPalette.moss.opacity(0.55), lineWidth: 1)
                }
                .position(x: x, y: max(14, height - 22 - cursorHeight - 12))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(isDragging || reduceMotion ? nil : PosterMotion.flow, value: yearLabel)
        }
    }

    private func sparseScale(width: CGFloat, height: CGFloat) -> some View {
        let landmarks: [(String, Double)] = [
            ("-100", -1),
            ("NOW", 0),
            ("+100", 1)
        ]

        return ZStack {
            ForEach(Array(landmarks.enumerated()), id: \.offset) { _, landmark in
                Text(landmark.0)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(
                        landmark.1 == 0 ? landmarkNowColor : landmarkColor
                    )
                    .position(
                        x: normalizedToX(landmark.1, width: width),
                        y: height - 8
                    )
            }
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    isDragging = true
                }
                let normalized = xToNormalized(gesture.location.x, width: width)
                dragValue = normalized
                onChange(normalized)
                updateHapticBucket(for: normalized)
            }
            .onEnded { gesture in
                let normalized = xToNormalized(gesture.location.x, width: width)
                let snapped = WaveTimeBrowseSnap.snap(TimePosition(normalized: normalized))
                dragValue = nil
                isDragging = false
                onChange(snapped.normalized)
                updateHapticBucket(for: snapped.normalized)
            }
    }

    private func updateHapticBucket(for normalized: Double) {
        // Sparse ticks: NOW band + decade crossings (MOTION_SPEC).
        let years = TimePosition(normalized: normalized).offsetYears
        let bucket: Int
        if abs(years) < 0.5 {
            bucket = 0
        } else {
            let decade = Int((years / 10).rounded()) * 10
            bucket = decade == 0 ? (years < 0 ? -10 : 10) : decade
        }
        if hapticBucket != bucket {
            hapticBucket = bucket
        }
    }

    private func normalizedToX(_ normalized: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(normalized, -1), 1)
        let usableWidth = max(1, width - horizontalInset * 2)
        return horizontalInset + CGFloat((clamped + 1) / 2) * usableWidth
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

/// Release / accessibility snap to browse-friendly date granularity.
/// Does **not** snap to landmark anchors (−100 / −30 / NOW / +30 / +100).
enum WaveTimeBrowseSnap {
    static func snap(_ position: TimePosition) -> TimePosition {
        let days = position.offsetDays
        let absDays = abs(days)
        guard absDays >= 0.5 else { return .now }

        let snappedDays: Double
        if absDays < 31 {
            snappedDays = days.rounded()
        } else if absDays < 365.25 {
            snappedDays = (days / 7).rounded() * 7
        } else if absDays < 3_652.5 {
            snappedDays = (days / 30.44).rounded() * 30.44
        } else {
            snappedDays = (days / 365.25).rounded() * 365.25
        }
        return TimePosition(offsetDays: snappedDays)
    }
}

#Preview("Wave on paper") {
    struct PreviewWrapper: View {
        @State private var value = 0.0

        var body: some View {
            VStack(spacing: PosterSpacing.lg) {
                Text(TimePosition(normalized: value).compactLabel)
                    .font(.headline)
                    .foregroundStyle(PosterPalette.ink)

                WaveTimeRail(value: value) { value = $0 }
                    .padding(.horizontal, PosterSpacing.lg)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PosterPalette.paper)
        }
    }
    return PreviewWrapper()
}

#Preview("Wave on sky wash") {
    struct PreviewWrapper: View {
        @State private var value = 0.35

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [PosterPalette.sky.opacity(0.35), PosterPalette.paper],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                WaveTimeRail(value: value) { value = $0 }
                    .padding(.horizontal, PosterSpacing.lg)
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Wave immersive") {
    struct PreviewWrapper: View {
        @State private var value = -0.2

        var body: some View {
            ZStack {
                PosterPalette.ink
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

                VStack {
                    Spacer()
                    WaveTimeRail(value: value, chrome: .immersive) { value = $0 }
                        .padding(.horizontal, PosterSpacing.lg)
                        .padding(.bottom, PosterSpacing.xl)
                }
            }
        }
    }
    return PreviewWrapper()
}

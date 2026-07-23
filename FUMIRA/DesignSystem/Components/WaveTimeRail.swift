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
    var onDetent: (WaveTimeDetent) -> Void = { _ in }
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragValue: Double?
    @State private var releaseValue: Double?
    @State private var releaseImpact = 0.0
    @State private var releaseTask: Task<Void, Never>?
    @State private var dragStartValue: Double?
    @State private var isDragging = false
    @State private var lastHapticYears: Double?

    private let horizontalInset: CGFloat = 16
    private let barMaxHeight: CGFloat = 40
    private let barMinHeight: CGFloat = 8
    private let railHeight: CGFloat = 88
    private let barCount = WaveformGeometry.defaultBarCount

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

    private var displayValue: Double {
        dragValue ?? releaseValue ?? value
    }

    private var timePosition: TimePosition {
        TimePosition(normalized: displayValue)
    }

    private var yearLabel: String {
        let year = Calendar.current.component(.year, from: timePosition.targetDate())
        return "\(year)"
    }

    private var continuousIndex: Double {
        WaveformGeometry.continuousIndex(normalized: displayValue, barCount: barCount)
    }

    var body: some View {
        VStack(spacing: PosterSpacing.sm) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let thumbX = normalizedToX(displayValue, width: width)

                ZStack {
                    waveCanvas(width: width, height: proxy.size.height, thumbX: thumbX)
                        .allowsHitTesting(false)

                    yearBadge(at: thumbX, height: proxy.size.height)
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
            let adjusted = WaveTimeAccessibilityAdjustment.adjustedNormalized(
                from: value,
                direction: direction == .increment ? .increment : .decrement
            )
            onChange(adjusted)
            emitAccessibilityDetent(from: value, to: adjusted)
        }
        .onDisappear {
            releaseTask?.cancel()
        }
    }

    private var accessibilityValueText: String {
        if abs(timePosition.offsetDays) < 0.5 {
            return "现在，\(yearLabel) 年"
        }
        let direction = timePosition.offsetDays < 0 ? "向过去" : "向未来"
        return "\(timePosition.compactLabel)，目标 \(yearLabel) 年，\(direction)"
    }

    private func waveCanvas(width: CGFloat, height: CGFloat, thumbX: CGFloat) -> some View {
        let usable = max(1, width - horizontalInset * 2)
        let spacing = usable / CGFloat(max(1, barCount - 1))
        let barWidth = max(2.5, spacing * 0.42)
        let centerY = height - 22 - barMaxHeight / 2
        let u = continuousIndex
        let impact = releaseImpact

        return Canvas { context, size in
            var axle = Path()
            axle.move(to: CGPoint(x: horizontalInset, y: centerY))
            axle.addLine(to: CGPoint(x: width - horizontalInset, y: centerY))
            context.stroke(
                axle,
                with: .color(idleBarColor.opacity(0.24)),
                lineWidth: 1
            )

            for index in 0..<barCount {
                let distance = abs(Double(index) - u)
                let resonance = exp(-0.5 * pow(distance / 2.1, 2)) * impact * 0.14
                let relative = min(
                    WaveformGeometry.ordinaryCapRatio,
                    WaveformGeometry.ordinaryRelativeHeight(at: index, selectedIndex: u) + resonance
                )
                let barHeight = barMinHeight + (barMaxHeight - barMinHeight) * relative
                let x = horizontalInset + CGFloat(index) * spacing
                let rect = CGRect(
                    x: x - barWidth / 2,
                    y: centerY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                let path = RoundedRectangle(cornerRadius: PosterRadius.waveBar, style: .continuous)
                    .path(in: rect)
                context.fill(path, with: .color(idleBarColor))
            }

            let activeHeight = barMaxHeight * (1 + impact * 0.14)
            let activeRect = CGRect(
                x: thumbX - barWidth / 2,
                y: centerY - activeHeight / 2,
                width: barWidth,
                height: activeHeight
            )
            let activePath = Capsule(style: .continuous).path(in: activeRect)
            context.fill(activePath, with: .color(PosterPalette.leafGreen))
        }
        .frame(width: width, height: height)
        .animation(isDragging || reduceMotion ? nil : PosterMotion.timeRailSettle, value: displayValue)
        .animation(reduceMotion ? nil : PosterMotion.timeRailKick, value: releaseImpact)
    }

    private func yearBadge(at x: CGFloat, height: CGFloat) -> some View {
        let centerY = height - 22 - barMaxHeight / 2

        return Text(yearLabel)
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
                    .stroke(PosterPalette.leafGreen.opacity(0.55), lineWidth: 1)
            }
            .position(x: x, y: max(14, centerY - barMaxHeight / 2 - 12))
            .offset(y: -3 * releaseImpact)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(isDragging || reduceMotion ? nil : PosterMotion.timeRailSettle, value: yearLabel)
            .animation(reduceMotion ? nil : PosterMotion.timeRailKick, value: releaseImpact)
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
                    releaseTask?.cancel()
                    releaseTask = nil
                    releaseValue = nil
                    releaseImpact = 0
                    isDragging = true
                    lastHapticYears = nil
                }
                let normalized = xToNormalized(gesture.location.x, width: width)
                if dragStartValue == nil {
                    dragStartValue = normalized
                }
                dragValue = normalized
                onChange(normalized)
                updateHaptics(for: normalized)
            }
            .onEnded { gesture in
                let normalized = xToNormalized(gesture.location.x, width: width)
                let predicted = xToNormalized(gesture.predictedEndLocation.x, width: width)
                let snapped = WaveTimeBrowseSnap.snap(TimePosition(normalized: normalized))
                let didMove = abs(normalized - (dragStartValue ?? normalized)) > 0.001
                let direction = WaveTimeRollPhysics.releaseDirection(
                    current: normalized,
                    predicted: predicted
                )
                let kick = WaveTimeRollPhysics.releaseKick(current: normalized, predicted: predicted)

                releaseTask?.cancel()
                dragValue = nil
                isDragging = false
                lastHapticYears = nil
                dragStartValue = nil

                guard didMove, !reduceMotion, direction != 0, kick > 0 else {
                    releaseValue = nil
                    releaseImpact = 0
                    onChange(snapped.normalized)
                    if didMove {
                        emitReleaseDetent(for: snapped)
                    }
                    return
                }

                // The model snaps immediately; only the presentation layer gets
                // a brief directional stroke before it locks back into position.
                releaseValue = normalized
                withAnimation(PosterMotion.timeRailKick) {
                    releaseValue = WaveTimeRollPhysics.overshoot(
                        target: snapped.normalized,
                        direction: direction,
                        kick: kick
                    )
                    releaseImpact = WaveTimeRollPhysics.impact(for: kick)
                }
                onChange(snapped.normalized)
                emitReleaseDetent(for: snapped)

                releaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(70))
                    guard !Task.isCancelled else { return }
                    withAnimation(PosterMotion.timeRailSettle) {
                        releaseValue = snapped.normalized
                        releaseImpact = 0
                    }

                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    releaseValue = nil
                    releaseTask = nil
                }
            }
    }

    private func emitReleaseDetent(for snapped: TimePosition) {
        onDetent(abs(snapped.offsetDays) < 0.5 ? .now : .decade)
    }

    private func updateHaptics(for normalized: Double) {
        let currentYears = TimePosition(normalized: normalized).offsetYears
        guard let previous = lastHapticYears else {
            lastHapticYears = currentYears
            return
        }
        guard WaveTimeHapticCrossing.shouldTick(previousYears: previous, currentYears: currentYears) else {
            lastHapticYears = currentYears
            return
        }
        let detent: WaveTimeDetent = WaveTimeHapticCrossing.crossedNow(
            previousYears: previous,
            currentYears: currentYears
        ) ? .now : .decade
        onDetent(detent)
        lastHapticYears = currentYears
    }

    private func emitAccessibilityDetent(from oldValue: Double, to newValue: Double) {
        let previous = TimePosition(normalized: oldValue).offsetYears
        let current = TimePosition(normalized: newValue).offsetYears
        let detent: WaveTimeDetent = WaveTimeHapticCrossing.crossedNow(
            previousYears: previous,
            currentYears: current
        ) ? .now : .decade
        onDetent(detent)
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
            .background(PosterPalette.canvas)
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

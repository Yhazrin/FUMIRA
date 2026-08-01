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
    /// When an external continuous input (for example device tilt) owns
    /// `value`, render each publication directly instead of retargeting the
    /// rail's implicit settle animation. Local drag/release motion is unchanged.
    var isExternalValueDirectDriven = false
    var onDetent: (WaveTimeDetent) -> Void = { _ in }
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragValue: Double?
    @State private var releaseValue: Double?
    @State private var releaseImpact = 0.0
    @State private var releaseTask: Task<Void, Never>?
    @State private var dragStartValue: Double?
    @State private var dragOriginPosition: TimePosition?
    @State private var dragStartGranularity: WaveTimeGranularity?
    @State private var granularity: WaveTimeGranularity = .year
    @State private var isDragging = false
    @State private var lastHapticYears: Double?
    @State private var lastModelPublication = Date.distantPast

    private let horizontalInset: CGFloat = 20
    private let barMaxHeight: CGFloat = 40
    private let barMinHeight: CGFloat = 8
    /// Wave + year badge only. Landmark labels live in a separate row below.
    private let barAreaHeight: CGFloat = 64
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

    private var timeLabel: String {
        granularity.compactValueLabel(for: timePosition)
    }

    private var continuousIndex: Double {
        WaveformGeometry.continuousIndex(normalized: displayValue, barCount: barCount)
    }

    private var animatesPresentedValueChanges: Bool {
        WaveTimeRailValueAnimationPolicy.shouldAnimate(
            isDragging: isDragging,
            reduceMotion: reduceMotion,
            isExternalValueDirectDriven: isExternalValueDirectDriven,
            isReleasePresentationActive: releaseValue != nil
        )
    }

    var body: some View {
        VStack(spacing: PosterSpacing.xs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let thumbX = normalizedToX(displayValue, width: width)

                ZStack {
                    waveCanvas(width: width, height: proxy.size.height, thumbX: thumbX)
                        .allowsHitTesting(false)

                    timeBadge(at: thumbX, height: proxy.size.height)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width))
            }
            .frame(height: barAreaHeight)

            landmarkLabelsRow
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间轴")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("左右拖动时间；向上拉依次进入月、日、小时精调，向下拉回到更粗粒度")
        .accessibilityAdjustableAction { direction in
            let delta = granularity.snapIntervalDays
                * (direction == .increment ? 1 : -1)
            let adjusted = TimePosition(
                offsetDays: TimePosition(normalized: value).offsetDays + delta
            )
            onChange(adjusted.normalized)
            emitAccessibilityDetent(from: value, to: adjusted.normalized)
        }
        .accessibilityAction(named: Text("更精细")) {
            selectGranularity(granularity.finer)
        }
        .accessibilityAction(named: Text("更粗略")) {
            selectGranularity(granularity.coarser)
        }
        .onDisappear {
            releaseTask?.cancel()
        }
    }

    private var accessibilityValueText: String {
        if abs(timePosition.offsetDays) < 0.5 {
            return "现在，\(timeLabel)"
        }
        let direction = timePosition.offsetDays < 0 ? "向过去" : "向未来"
        return "\(timePosition.compactLabel)，目标 \(timeLabel)，\(direction)"
    }

    private func waveCanvas(width: CGFloat, height: CGFloat, thumbX: CGFloat) -> some View {
        let usable = max(1, width - horizontalInset * 2)
        let spacing = usable / CGFloat(max(1, barCount - 1))
        let barWidth = max(2.5, spacing * 0.42)
        // Leave headroom for the floating year badge above the tallest bar.
        let centerY = height - 6 - barMaxHeight / 2
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
            context.fill(activePath, with: .color(PosterPalette.actionBlue))
        }
        .frame(width: width, height: height)
        .animation(
            animatesPresentedValueChanges ? PosterMotion.timeRailSettle : nil,
            value: displayValue
        )
        .animation(reduceMotion ? nil : PosterMotion.timeRailKick, value: releaseImpact)
    }

    private func timeBadge(at x: CGFloat, height: CGFloat) -> some View {
        let centerY = height - 6 - barMaxHeight / 2

        return Text(timeLabel)
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
                    .stroke(PosterPalette.actionBlue.opacity(0.55), lineWidth: 1)
            }
            .position(x: x, y: max(12, centerY - barMaxHeight / 2 - 11))
            .offset(y: -3 * releaseImpact)
            .contentTransition(
                animatesPresentedValueChanges ? .numericText() : .identity
            )
            .animation(
                animatesPresentedValueChanges ? PosterMotion.timeRailSettle : nil,
                value: timeLabel
            )
            .animation(reduceMotion ? nil : PosterMotion.timeRailKick, value: releaseImpact)
    }

    private var landmarkLabelsRow: some View {
        HStack {
            Text("-100")
                .foregroundStyle(landmarkColor)
                .frame(minWidth: 32, alignment: .leading)
            Spacer(minLength: 0)
            Text("NOW")
                .foregroundStyle(landmarkNowColor)
            Spacer(minLength: 0)
            Text("+100")
                .foregroundStyle(landmarkColor)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, horizontalInset)
        .accessibilityHidden(true)
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
                    lastModelPublication = .distantPast
                    dragOriginPosition = TimePosition(normalized: value)
                    dragStartGranularity = granularity
                }
                if dragStartValue == nil {
                    dragStartValue = value
                }
                let resolvedGranularity = (
                    dragStartGranularity ?? granularity
                ).offsetting(verticalTranslation: gesture.translation.height)
                if granularity != resolvedGranularity {
                    granularity = resolvedGranularity
                    onDetent(.decade)
                }
                let normalized = resolvedPosition(
                    for: gesture,
                    width: width,
                    granularity: resolvedGranularity
                ).normalized
                dragValue = normalized
                publishModelValueIfNeeded(normalized)
                updateHaptics(for: normalized)
            }
            .onEnded { gesture in
                let resolvedGranularity = (
                    dragStartGranularity ?? granularity
                ).offsetting(verticalTranslation: gesture.translation.height)
                granularity = resolvedGranularity
                let normalized = resolvedPosition(
                    for: gesture,
                    width: width,
                    granularity: resolvedGranularity
                ).normalized
                let predicted = predictedPosition(
                    for: gesture,
                    width: width,
                    granularity: resolvedGranularity
                ).normalized
                let snapped = resolvedGranularity.snap(
                    TimePosition(normalized: normalized)
                )
                let didMove = abs(normalized - (dragStartValue ?? normalized)) > 0.001
                    || resolvedGranularity != dragStartGranularity
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
                dragOriginPosition = nil
                dragStartGranularity = nil

                guard didMove, !reduceMotion, direction != 0, kick > 0 else {
                    releaseValue = nil
                    releaseImpact = 0
                    publishModelValue(snapped.normalized)
                    if didMove {
                        emitReleaseDetent(for: snapped)
                    }
                    return
                }

                // The model snaps immediately; only the presentation layer gets
                // a brief directional stroke before it locks back into position.
                // Keep the kick short so ProMotion (120Hz) reads as one clean tick.
                releaseValue = normalized
                withAnimation(.timingCurve(0.12, 0.94, 0.20, 1, duration: 0.055)) {
                    releaseValue = WaveTimeRollPhysics.overshoot(
                        target: snapped.normalized,
                        direction: direction,
                        kick: kick
                    )
                    releaseImpact = WaveTimeRollPhysics.impact(for: kick)
                }
                publishModelValue(snapped.normalized)
                emitReleaseDetent(for: snapped)

                releaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(55))
                    guard !Task.isCancelled else { return }
                    withAnimation(.timingCurve(0.18, 0.86, 0.24, 1, duration: 0.16)) {
                        releaseValue = snapped.normalized
                        releaseImpact = 0
                    }

                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    releaseValue = nil
                    releaseTask = nil
                }
            }
    }

    private func resolvedPosition(
        for gesture: DragGesture.Value,
        width: CGFloat,
        granularity: WaveTimeGranularity
    ) -> TimePosition {
        if granularity == .year, dragStartGranularity == .year {
            return TimePosition(
                normalized: xToNormalized(gesture.location.x, width: width)
            )
        }
        return granularity.position(
            from: dragOriginPosition ?? TimePosition(normalized: value),
            horizontalTranslation: gesture.translation.width,
            usableWidth: width - horizontalInset * 2
        )
    }

    private func predictedPosition(
        for gesture: DragGesture.Value,
        width: CGFloat,
        granularity: WaveTimeGranularity
    ) -> TimePosition {
        if granularity == .year, dragStartGranularity == .year {
            return TimePosition(
                normalized: xToNormalized(
                    gesture.predictedEndLocation.x,
                    width: width
                )
            )
        }
        return granularity.position(
            from: dragOriginPosition ?? TimePosition(normalized: value),
            horizontalTranslation: gesture.predictedEndTranslation.width,
            usableWidth: width - horizontalInset * 2
        )
    }

    private func publishModelValueIfNeeded(_ normalized: Double) {
        let now = Date.now
        guard WaveTimeModelPublicationGate.shouldPublish(
            lastPublishedAt: lastModelPublication,
            now: now
        ) else {
            return
        }
        lastModelPublication = now
        onChange(normalized)
    }

    private func publishModelValue(_ normalized: Double) {
        lastModelPublication = Date.now
        onChange(normalized)
    }

    /// VoiceOver granularity changes are local presentation state. Keeping
    /// them separate from `onChange` preserves the selected target time and
    /// cannot enter the generation path.
    private func selectGranularity(_ selection: WaveTimeGranularity) {
        guard selection != granularity else { return }
        granularity = selection
        onDetent(.decade)
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

/// Keeps the external direct-drive contract independently testable without
/// exposing SwiftUI transaction details to feature code.
enum WaveTimeRailValueAnimationPolicy {
    static func shouldAnimate(
        isDragging: Bool,
        reduceMotion: Bool,
        isExternalValueDirectDriven: Bool,
        isReleasePresentationActive: Bool
    ) -> Bool {
        guard !isDragging, !reduceMotion else { return false }
        return !isExternalValueDirectDriven || isReleasePresentationActive
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

    static func snap(
        _ position: TimePosition,
        granularity: WaveTimeGranularity
    ) -> TimePosition {
        granularity.snap(position)
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

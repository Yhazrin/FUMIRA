import SwiftUI

/// Viewfinder time rail whose selection cursor *is* the shutter.
///
/// Idle: neighboring white bars fuse into the blue-and-white circular shutter
/// (as if the two side strokes + the blue selection bar became one button).
/// Scrubbing: the circle elastically contracts into the thin blue rail bar
/// while the fused neighbors reappear as ordinary waveform strokes.
/// Release: the bar expands back into the shutter and re-absorbs its neighbors.
struct ShutterWaveTimeRail: View {
    let value: Double
    var onDetent: (WaveTimeDetent) -> Void = { _ in }
    let onChange: (Double) -> Void
    var onShutterPress: () -> Void = {}
    let onCapture: () -> Void
    /// Keeps year + landmark labels upright when the phone is held sideways.
    var chromeRotation: Angle = .zero

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
    /// 0 = circular shutter, 1 = thin blue rail bar.
    #if DEBUG
    @State private var morphProgress: CGFloat =
        ProcessInfo.processInfo.environment["FUMIRA_AUDIT_SHUTTER_MORPH"] == "half" ? 0.5 : 0
    @State private var touchBeganOnShutter =
        ProcessInfo.processInfo.environment["FUMIRA_AUDIT_SHUTTER"] == "pressed"
    #else
    @State private var morphProgress: CGFloat = 0
    @State private var touchBeganOnShutter = false
    #endif

    /// Wave bars reach near the screen edges.
    private let barInset: CGFloat = 10
    /// Thumb/shutter stays inset so the idle circle never clips.
    private let thumbInset: CGFloat = 36
    private let barMaxHeight: CGFloat = 44
    private let barMinHeight: CGFloat = 8
    private let stageHeight = CameraChromeMetrics.waveRailStageHeight
    private let barCount = WaveformGeometry.defaultBarCount
    private let shutterDiameter: CGFloat = 68
    private let railBarWidth: CGFloat = 5
    private let scrubMorphThreshold: CGFloat = 3

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

    /// The cursor conversion must finish before the next hand movement is
    /// interpreted as a scrub. A monotonic curve avoids a spring fighting the
    /// directly controlled thumb position.
    private var morphInAnimation: Animation {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.cameraShutterMorph
    }

    /// Same curve in reverse: the control is an optical state change, not a
    /// bouncing physical key.
    private var morphOutAnimation: Animation {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : PosterMotion.cameraShutterMorph
    }

    var body: some View {
        VStack(spacing: ClaySpacing.xxs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let thumbX = normalizedToX(displayValue, width: width)
                let centerY = proxy.size.height * 0.58

                ZStack {
                    WaveformPartingCanvas(
                        centerY: centerY,
                        thumbX: thumbX,
                        continuousIndex: continuousIndex,
                        releaseImpact: releaseImpact,
                        morphProgress: morphProgress,
                        barInset: barInset,
                        barCount: barCount,
                        barMaxHeight: barMaxHeight,
                        barMinHeight: barMinHeight
                    )
                    .allowsHitTesting(false)

                    MorphingShutterCursor(
                        morphProgress: morphProgress,
                        isPressed: touchBeganOnShutter && !isDragging,
                        shutterDiameter: shutterDiameter,
                        barWidth: railBarWidth,
                        barHeight: barMaxHeight * (1 + CGFloat(releaseImpact) * 0.12),
                        neighborSpacing: max(
                            1,
                            (width - barInset * 2) / CGFloat(max(1, barCount - 1))
                        )
                    )
                    .position(x: thumbX, y: centerY)
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width, thumbX: thumbX))
            }
            .frame(height: stageHeight)

            scrubbingYearCapsule
        }
        .frame(height: CameraChromeMetrics.waveRailHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间轴与快门")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("左右拖动时间，向上拉进入月、日、小时精调；轻点蓝白快门拍摄")
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
        .accessibilityAction(named: Text("拍摄")) {
            onCapture()
        }
        .onDisappear {
            releaseTask?.cancel()
        }
    }

    private var accessibilityValueText: String {
        let days = timePosition.offsetDays
        guard days.isFinite else { return "现在" }
        if abs(days) < 0.5 {
            return "现在，\(timeLabel)"
        }
        let direction = days < 0 ? "向过去" : "向未来"
        return "\(timePosition.compactLabel)，目标 \(timeLabel)，\(direction)"
    }

    /// "Year" capsule that floats above the wave rail while the user is
    /// actively scrubbing. Hidden when the rail is idle. Replaces the old
    /// "-100 / NOW / +100" landmark strip and is less prescriptive: the
    /// caption just reads the current year.
    private var scrubbingYearCapsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption2.weight(.bold))
                .foregroundStyle(ClayPalette.orange)
            Text(timeLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(ClayPalette.warmWhite)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(ClayPalette.charcoal)
        .clipShape(Capsule())
        .overlay {
            Capsule(style: .continuous)
                .stroke(ClayPalette.warmWhite.opacity(0.18), lineWidth: 0.5)
        }
        .rotationEffect(chromeRotation)
        .opacity(isDragging ? 1 : 0)
        .scaleEffect(isDragging ? 1 : 0.86)
        .animation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : PosterMotion.cameraShutterMorph,
            value: isDragging
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityHidden(true)
    }

    // MARK: - Gesture

    private func dragGesture(width: CGFloat, thumbX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStartValue == nil {
                    releaseTask?.cancel()
                    releaseTask = nil
                    releaseValue = nil
                    releaseImpact = 0
                    lastHapticYears = nil
                    lastModelPublication = .distantPast
                    touchBeganOnShutter = abs(gesture.startLocation.x - thumbX) <= shutterDiameter * 0.55
                    if touchBeganOnShutter {
                        onShutterPress()
                    }
                    dragStartValue = value
                    dragOriginPosition = TimePosition(normalized: value)
                    dragStartGranularity = granularity
                }

                let resolvedGranularity = (
                    dragStartGranularity ?? granularity
                ).offsetting(verticalTranslation: gesture.translation.height)
                if granularity != resolvedGranularity {
                    granularity = resolvedGranularity
                    onDetent(.decade)
                }

                let travel = max(
                    abs(gesture.translation.width),
                    abs(gesture.translation.height)
                )
                if travel >= scrubMorphThreshold {
                    if !isDragging {
                        isDragging = true
                        // Morph runs independently; the scrub position stays
                        // 1:1 with the finger from the very next sample.
                        withAnimation(morphInAnimation) {
                            morphProgress = 1
                        }
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
                let startedOnShutter = touchBeganOnShutter
                let translationX = abs(gesture.translation.width)
                let translationY = abs(gesture.translation.height)
                // Shutter taps must not depend on the mapped time delta: the
                // finger can land anywhere inside the circle, which already
                // differs from the model value by more than 0.001.
                let isShutterTap = startedOnShutter
                    && !isDragging
                    && translationX < scrubMorphThreshold
                    && translationY < scrubMorphThreshold
                let didMove = isDragging
                    || translationX >= scrubMorphThreshold
                    || translationY >= scrubMorphThreshold
                    || abs(normalized - (dragStartValue ?? normalized)) > 0.001

                releaseTask?.cancel()
                dragValue = nil
                lastHapticYears = nil
                let retainedStartValue = dragStartValue
                dragStartValue = nil
                dragOriginPosition = nil
                dragStartGranularity = nil
                touchBeganOnShutter = false

                // Expand first with spring, then settle the date kick.
                withAnimation(morphOutAnimation) {
                    isDragging = false
                    morphProgress = 0
                }

                if isShutterTap {
                    publishModelValue(retainedStartValue ?? value)
                    onCapture()
                    return
                }

                if !didMove {
                    publishModelValue(snapped.normalized)
                    return
                }

                let direction = WaveTimeRollPhysics.releaseDirection(
                    current: normalized,
                    predicted: predicted
                )
                let kick = WaveTimeRollPhysics.releaseKick(current: normalized, predicted: predicted)

                guard !reduceMotion, direction != 0, kick > 0 else {
                    releaseValue = nil
                    releaseImpact = 0
                    publishModelValue(snapped.normalized)
                    emitReleaseDetent(for: snapped)
                    return
                }

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
            usableWidth: width - thumbInset * 2
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
            usableWidth: width - thumbInset * 2
        )
    }

    private func emitReleaseDetent(for snapped: TimePosition) {
        onDetent(abs(snapped.offsetDays) < 0.5 ? .now : .decade)
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

    /// Granularity is a local browsing precision. VoiceOver can change it
    /// without publishing a new time or invoking the shutter/generation path.
    private func selectGranularity(_ selection: WaveTimeGranularity) {
        guard selection != granularity else { return }
        granularity = selection
        onDetent(.decade)
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
        let usableWidth = max(1, width - thumbInset * 2)
        return thumbInset + CGFloat((clamped + 1) / 2) * usableWidth
    }

    private func xToNormalized(_ x: CGFloat, width: CGFloat) -> Double {
        let usableWidth = max(1, width - thumbInset * 2)
        let clamped = min(max((x - thumbInset) / usableWidth, 0), 1)
        return Double(clamped * 2 - 1)
    }
}

// MARK: - Fusion waveform

/// Neighbor bars fuse into the idle shutter instead of being crushed aside.
/// Height envelope stays selection-relative for bars that remain visible.
private struct WaveformPartingCanvas: View {
    var centerY: CGFloat
    var thumbX: CGFloat
    var continuousIndex: Double
    var releaseImpact: Double
    var morphProgress: CGFloat
    var barInset: CGFloat
    var barCount: Int
    var barMaxHeight: CGFloat
    var barMinHeight: CGFloat

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
            let width = size.width
            let usable = max(1, width - barInset * 2)
            let spacing = usable / CGFloat(max(1, barCount - 1))
            let strokeWidth = max(2.5, spacing * 0.42)
            let openAmount = 1 - morphProgress
            // Gentle outer nudge only — no hard pocket that compresses neighbors.
            let softClearance = spacing * 0.85 * openAmount

            for index in 0..<barCount {
                let naturalX = barInset + CGFloat(index) * spacing
                let delta = naturalX - thumbX
                let absDelta = abs(delta)
                let indexDist = abs(Double(index) - continuousIndex)

                // ~1–1.5 nearest bars on each side dissolve into the shutter.
                let fusionLinear = max(0, 1 - indexDist / 1.55) * openAmount
                let fusion = fusionLinear * fusionLinear

                // Bars just outside the fusion core get a soft outward breath.
                let outerBand = max(0, 1 - absDelta / max(spacing * 3.8, 1))
                let outerInfluence = outerBand * (1 - fusion)
                let push = (delta >= 0 ? 1.0 : -1.0) * softClearance * outerInfluence * outerInfluence

                // Absorb toward the thumb as they fuse.
                let absorbX = naturalX + (thumbX - naturalX) * fusion
                let drawnX = min(max(absorbX + push, barInset), width - barInset)

                let distance = abs(Double(index) - continuousIndex)
                let resonance = exp(-0.5 * pow(distance / 2.1, 2)) * releaseImpact * 0.14
                let relative = min(
                    WaveformGeometry.ordinaryCapRatio,
                    WaveformGeometry.ordinaryRelativeHeight(
                        at: index,
                        selectedIndex: continuousIndex
                    ) + resonance
                )
                let envelopeHeight = barMinHeight + (barMaxHeight - barMinHeight) * relative
                // Fusing bars shrink into the button; remaining bars keep full envelope.
                let barHeight = envelopeHeight * (1 - fusion * 0.78)
                let barWidth = strokeWidth * (1 - fusion * 0.55)
                let opacity = 0.38 * (1 - fusion)

                if opacity > 0.03 {
                    let renderedWidth = max(1.2, barWidth)
                    let renderedHeight = max(barMinHeight * (1 - fusion), barHeight)
                    let rect = CGRect(
                        x: drawnX - renderedWidth * 0.5,
                        y: centerY - renderedHeight * 0.5,
                        width: renderedWidth,
                        height: renderedHeight
                    )
                    context.fill(
                        Path(
                            roundedRect: rect,
                            cornerRadius: min(renderedWidth, renderedHeight) * 0.5
                        ),
                        with: .color(ClayPalette.warmWhite.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Morphing cursor

/// Circle shutter ↔ thin blue selection bar, with side ghosts that read as
/// “neighbor bars merging into / emerging from” the control.
private struct MorphingShutterCursor: View {
    var morphProgress: CGFloat
    var isPressed: Bool
    var shutterDiameter: CGFloat
    var barWidth: CGFloat
    var barHeight: CGFloat
    var neighborSpacing: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var openAmount: CGFloat { 1 - morphProgress }

    private var morphSize: CGSize {
        ShutterMorphGeometry.size(
            progress: morphProgress,
            shutterDiameter: shutterDiameter,
            barWidth: barWidth,
            barHeight: barHeight
        )
    }

    private var ringOpacity: Double {
        Double(max(0, 1 - morphProgress * 1.25))
    }

    private var pressScale: CGFloat {
        guard !reduceMotion, isPressed else { return 1 }
        return PosterMotion.cameraShutterPressedScale
    }

    /// Peaks mid-morph: ghosts visible while bars are mid-fusion.
    private var ghostStrength: CGFloat {
        let peak = openAmount * morphProgress * 4
        return min(1, peak)
    }

    var body: some View {
        ZStack {
            // Collapsing / emerging neighbor accents during the morph.
            ForEach([-1, 1], id: \.self) { side in
                let sideOffset = CGFloat(side) * (
                    neighborSpacing * (0.55 + 0.45 * morphProgress)
                        * (1 - openAmount * 0.92)
                )
                Capsule(style: .continuous)
                    .fill(
                        ClayPalette.orange.opacity(
                            Double(0.34 * ghostStrength * (0.55 + 0.45 * morphProgress))
                        )
                    )
                    .frame(
                        width: barWidth * (1.05 - 0.35 * openAmount),
                        height: barHeight * (0.72 + 0.28 * morphProgress)
                    )
                    .offset(x: sideOffset)
            }

            // One flat surface: circular at rest, then continuously narrows
            // into the active time bar. Press feedback comes from scale +
            // haptics, never from a second pedestal or simulated button depth.
            Capsule(style: .continuous)
                .fill(ClayPalette.warmWhite.opacity(0.96))
                .overlay {
                    Capsule(style: .continuous)
                        .fill(ClayPalette.orange)
                        .opacity(morphProgress)
                }
                .frame(
                    width: max(barWidth, morphSize.width),
                    height: max(barWidth, morphSize.height)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(ClayPalette.orange.opacity(0.45), lineWidth: 1)
                        .opacity(ringOpacity)
                }

            Circle()
                .fill(ClayPalette.orange)
                .frame(width: 8, height: 8)
                .opacity(ringOpacity)
        }
        // Fix the animation canvas before applying any scale. This keeps the
        // morph anchored at its center instead of inheriting a changing origin.
        .frame(width: shutterDiameter, height: shutterDiameter, alignment: .center)
        // Bottom anchoring turns uniform compression into a short perceived
        // downward travel while the actual layout position remains unchanged.
        .scaleEffect(pressScale, anchor: .bottom)
        .animation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : (
                    isPressed
                        ? PosterMotion.cameraShutterPressDown
                        : PosterMotion.cameraShutterRelease
            ),
            value: isPressed
        )
        .accessibilityHidden(true)
    }
}

#Preview("Shutter wave rail") {
    struct PreviewWrapper: View {
        @State private var value = 0.0

        var body: some View {
            ZStack {
                ClayPalette.charcoal.ignoresSafeArea()
                VStack {
                    Spacer()
                    ShutterWaveTimeRail(value: value, onChange: { value = $0 }, onCapture: {})
                        .padding(.horizontal, ClaySpacing.lg)
                        .padding(.bottom, ClaySpacing.xxxl)
                }
            }
        }
    }
    return PreviewWrapper()
}

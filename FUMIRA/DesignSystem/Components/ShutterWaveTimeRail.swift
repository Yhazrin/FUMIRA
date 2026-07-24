import SwiftUI

/// Viewfinder time rail whose selection cursor *is* the shutter.
///
/// Idle: neighboring white bars fuse into the leaf-green circular shutter
/// (as if the two side strokes + the green selection bar became one button).
/// Scrubbing: the circle elastically contracts into the thin green rail bar
/// while the fused neighbors reappear as ordinary waveform strokes.
/// Release: the bar expands back into the shutter and re-absorbs its neighbors.
struct ShutterWaveTimeRail: View {
    let value: Double
    var onDetent: (WaveTimeDetent) -> Void = { _ in }
    let onChange: (Double) -> Void
    let onCapture: () -> Void
    /// Keeps year + landmark labels upright when the phone is held sideways.
    var chromeRotation: Angle = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragValue: Double?
    @State private var releaseValue: Double?
    @State private var releaseImpact = 0.0
    @State private var releaseTask: Task<Void, Never>?
    @State private var dragStartValue: Double?
    @State private var isDragging = false
    @State private var lastHapticYears: Double?
    /// 0 = circular shutter, 1 = thin green rail bar.
    @State private var morphProgress: CGFloat = 0
    @State private var touchBeganOnShutter = false

    /// Wave bars reach near the screen edges.
    private let barInset: CGFloat = 10
    /// Thumb/shutter stays inset so the idle circle never clips.
    private let thumbInset: CGFloat = 36
    private let barMaxHeight: CGFloat = 44
    private let barMinHeight: CGFloat = 8
    private let stageHeight: CGFloat = 100
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

    private var yearLabel: String {
        let year = Calendar.current.component(.year, from: timePosition.targetDate())
        return "\(year)"
    }

    private var continuousIndex: Double {
        WaveformGeometry.continuousIndex(normalized: displayValue, barCount: barCount)
    }

    /// Contract into the thin bar — a touch slower for readable morph.
    private var morphInAnimation: Animation {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : .spring(response: 0.56, dampingFraction: 0.80)
    }

    /// Expand back into the shutter — slower soft settle.
    private var morphOutAnimation: Animation {
        reduceMotion
            ? .linear(duration: PosterMotion.reduced)
            : .spring(response: 0.70, dampingFraction: 0.74)
    }

    var body: some View {
        VStack(spacing: PosterSpacing.xs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let thumbX = normalizedToX(displayValue, width: width)
                let centerY = proxy.size.height * 0.58

                ZStack {
                    WaveformPartingCanvas(
                        width: width,
                        height: proxy.size.height,
                        centerY: centerY,
                        thumbX: thumbX,
                        continuousIndex: continuousIndex,
                        releaseImpact: releaseImpact,
                        morphProgress: morphProgress,
                        barInset: barInset,
                        barCount: barCount,
                        barMaxHeight: barMaxHeight,
                        barMinHeight: barMinHeight,
                        shutterDiameter: shutterDiameter
                    )
                    .allowsHitTesting(false)

                    MorphingShutterCursor(
                        morphProgress: morphProgress,
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

            landmarkLabelsRow
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间轴与快门")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("左右拖动浏览过去与未来；轻点绿色快门拍摄")
        .accessibilityAdjustableAction { direction in
            let adjusted = WaveTimeAccessibilityAdjustment.adjustedNormalized(
                from: value,
                direction: direction == .increment ? .increment : .decrement
            )
            onChange(adjusted)
            emitAccessibilityDetent(from: value, to: adjusted)
        }
        .accessibilityAction(named: Text("拍摄")) {
            onCapture()
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

    private var landmarkLabelsRow: some View {
        HStack {
            Text("-100")
                .frame(minWidth: 32, alignment: .leading)
                .rotationEffect(chromeRotation)
            Spacer(minLength: 0)
            Text("NOW")
                .rotationEffect(chromeRotation)
            Spacer(minLength: 0)
            Text("+100")
                .frame(minWidth: 32, alignment: .trailing)
                .rotationEffect(chromeRotation)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(PosterPalette.paperWhite.opacity(0.7))
        .padding(.horizontal, barInset)
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
                    touchBeganOnShutter = abs(gesture.startLocation.x - thumbX) <= shutterDiameter * 0.55
                    dragStartValue = xToNormalized(gesture.location.x, width: width)
                }

                let travel = abs(gesture.translation.width)
                if travel >= scrubMorphThreshold {
                    if !isDragging {
                        isDragging = true
                        // Morph runs on its own spring; scrub position stays 1:1 with the finger.
                        withAnimation(morphInAnimation) {
                            morphProgress = 1
                        }
                    }
                    let normalized = xToNormalized(gesture.location.x, width: width)
                    dragValue = normalized
                    onChange(normalized)
                    updateHaptics(for: normalized)
                }
            }
            .onEnded { gesture in
                let normalized = xToNormalized(gesture.location.x, width: width)
                let predicted = xToNormalized(gesture.predictedEndLocation.x, width: width)
                let snapped = WaveTimeBrowseSnap.snap(TimePosition(normalized: normalized))
                let didMove = isDragging
                    || abs(gesture.translation.width) >= scrubMorphThreshold
                    || abs(normalized - (dragStartValue ?? normalized)) > 0.001
                let startedOnShutter = touchBeganOnShutter

                releaseTask?.cancel()
                dragValue = nil
                lastHapticYears = nil
                dragStartValue = nil
                touchBeganOnShutter = false

                // Expand first with spring, then settle the date kick.
                withAnimation(morphOutAnimation) {
                    isDragging = false
                    morphProgress = 0
                }

                if !didMove {
                    onChange(snapped.normalized)
                    if startedOnShutter {
                        onCapture()
                    }
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
                    onChange(snapped.normalized)
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
                onChange(snapped.normalized)
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
    var width: CGFloat
    var height: CGFloat
    var centerY: CGFloat
    var thumbX: CGFloat
    var continuousIndex: Double
    var releaseImpact: Double
    var morphProgress: CGFloat
    var barInset: CGFloat
    var barCount: Int
    var barMaxHeight: CGFloat
    var barMinHeight: CGFloat
    var shutterDiameter: CGFloat

    var body: some View {
        let usable = max(1, width - barInset * 2)
        let spacing = usable / CGFloat(max(1, barCount - 1))
        let strokeWidth = max(2.5, spacing * 0.42)
        let openAmount = 1 - morphProgress
        // Gentle outer nudge only — no hard pocket that compresses neighbors.
        let softClearance = spacing * 0.85 * openAmount

        ZStack {
            ForEach(0..<barCount, id: \.self) { index in
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
                    Capsule(style: .continuous)
                        .fill(PosterPalette.paperWhite.opacity(opacity))
                        .frame(
                            width: max(1.2, barWidth),
                            height: max(barMinHeight * (1 - fusion), barHeight)
                        )
                        .position(x: drawnX, y: centerY)
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

// MARK: - Morphing cursor

/// Circle shutter ↔ thin green selection bar, with side ghosts that read as
/// “neighbor bars merging into / emerging from” the control.
private struct MorphingShutterCursor: View {
    var morphProgress: CGFloat
    var shutterDiameter: CGFloat
    var barWidth: CGFloat
    var barHeight: CGFloat
    var neighborSpacing: CGFloat

    private var openAmount: CGFloat { 1 - morphProgress }

    /// Ease the size morph so fusion reads more continuous than a linear lerp.
    private var morphT: CGFloat {
        let t = morphProgress
        return t * t * (3 - 2 * t)
    }

    private var width: CGFloat {
        shutterDiameter + (barWidth - shutterDiameter) * morphT
    }

    private var height: CGFloat {
        shutterDiameter + (barHeight - shutterDiameter) * morphT
    }

    private var ringOpacity: Double {
        Double(max(0, 1 - morphProgress * 1.25))
    }

    private var shadowOpacity: Double {
        Double(max(0, openAmount) * 0.22)
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
                        PosterPalette.paperWhite.opacity(
                            Double(0.34 * ghostStrength * (0.55 + 0.45 * morphProgress))
                        )
                    )
                    .frame(
                        width: barWidth * (1.05 - 0.35 * openAmount),
                        height: barHeight * (0.72 + 0.28 * morphProgress)
                    )
                    .offset(x: sideOffset)
            }

            Capsule(style: .continuous)
                .fill(PosterPalette.leafGreen)
                .frame(width: max(barWidth, width), height: max(barWidth, height))
                .shadow(
                    color: PosterPalette.ink.opacity(shadowOpacity),
                    radius: 8 * openAmount,
                    y: 3 * openAmount
                )

            Capsule(style: .continuous)
                .stroke(
                    PosterPalette.skyDeep.opacity(0.42 * ringOpacity),
                    lineWidth: 2
                )
                .frame(
                    width: shutterDiameter * 0.79 * (1 - morphProgress * 0.9) + barWidth * morphProgress,
                    height: shutterDiameter * 0.79 * (1 - morphProgress * 0.9) + barWidth * morphProgress
                )
                .opacity(ringOpacity)
        }
        // Stable layout box so `.position` stays centered while the capsule morphs.
        .frame(width: shutterDiameter, height: shutterDiameter, alignment: .center)
        .accessibilityHidden(true)
    }
}

#Preview("Shutter wave rail") {
    struct PreviewWrapper: View {
        @State private var value = 0.0

        var body: some View {
            ZStack {
                PosterPalette.ink.ignoresSafeArea()
                VStack {
                    Spacer()
                    ShutterWaveTimeRail(value: value, onChange: { value = $0 }, onCapture: {})
                        .padding(.horizontal, PosterSpacing.md)
                        .padding(.bottom, PosterSpacing.xl)
                }
            }
        }
    }
    return PreviewWrapper()
}

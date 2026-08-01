import SwiftUI
import UIKit

enum TemporalBlinkComparatorMetrics {
    static let minimumTarget: CGFloat = 44
}

/// Full-frame astronomical blink comparison for an already aligned photo pair.
///
/// This complements the result screen's draggable boundary: hold the primary
/// control to inspect the original, explicitly toggle with VoiceOver, or run
/// one bounded slow comparison round. No cadence starts on appear or loops.
struct TemporalBlinkComparator: View {
    let originalImage: UIImage?
    let generatedImage: UIImage?
    let targetTime: TimePosition
    var cornerRadius: CGFloat = PosterRadius.photoPaper

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights
    @GestureState private var isHoldingOriginal = false
    @State private var lockedFrame: TemporalBlinkFrame
    @State private var cadenceFrame: TemporalBlinkFrame?
    @State private var cadenceTask: Task<Void, Never>?

    private let engine = TemporalBlinkComparatorEngine.standard

    init(
        originalImage: UIImage?,
        generatedImage: UIImage?,
        targetTime: TimePosition,
        initialFrame: TemporalBlinkFrame = .generated,
        cornerRadius: CGFloat = PosterRadius.photoPaper
    ) {
        self.originalImage = originalImage
        self.generatedImage = generatedImage
        self.targetTime = targetTime
        self.cornerRadius = cornerRadius
        _lockedFrame = State(initialValue: initialFrame)
    }

    var body: some View {
        ZStack {
            photoPair

            VStack(spacing: 0) {
                statusLabel
                Spacer(minLength: PosterSpacing.md)
                controlShelf
            }
            .padding(PosterSpacing.md)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                cancelCadence()
            }
        }
        .onChange(of: dimFlashingLights) { _, isEnabled in
            if isEnabled {
                cancelCadence()
            }
        }
        .onDisappear(perform: cancelCadence)
    }

    private var hasBothFrames: Bool {
        originalImage != nil && generatedImage != nil
    }

    private var visibleFrame: TemporalBlinkFrame {
        engine.visibleFrame(
            lockedFrame: lockedFrame,
            isHoldingOriginal: isHoldingOriginal,
            cadenceFrame: cadenceFrame
        )
    }

    private var cadenceIsAllowed: Bool {
        hasBothFrames && !reduceMotion && !dimFlashingLights
    }

    private var photoPair: some View {
        ZStack {
            PosterPalette.ink

            if let originalImage {
                comparisonImage(originalImage)
                    .opacity(visibleFrame == .original ? 1 : 0)
            }

            if let generatedImage {
                comparisonImage(generatedImage)
                    .opacity(visibleFrame == .generated ? 1 : 0)
            }

            if originalImage == nil, generatedImage == nil {
                PosterPalette.skySoft
            }
        }
        // Blink comparison depends on exact full-frame replacement. Parent
        // animations must not turn it into an uncoordinated crossfade.
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间对照照片")
        .accessibilityValue(frameAccessibilityValue)
    }

    private var statusLabel: some View {
        HStack(spacing: PosterSpacing.xs) {
            Image(systemName: visibleFrame == .original ? "camera" : "sparkles")
                .accessibilityHidden(true)

            Text(visibleFrame == .original ? "原片 · NOW" : targetTime.compactLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(PosterTypography.caption.weight(.semibold))
        .foregroundStyle(PosterPalette.paperWhite)
        .padding(.horizontal, PosterSpacing.sm)
        .padding(.vertical, PosterSpacing.xs)
        .background(PosterPalette.ink.opacity(0.72), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var controlShelf: some View {
        HStack(spacing: PosterSpacing.sm) {
            holdControl

            Button(action: startCadence) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(PosterTypography.label)
                    .foregroundStyle(PosterPalette.actionBlueDeep)
                    .frame(
                        width: TemporalBlinkComparatorMetrics.minimumTarget,
                        height: TemporalBlinkComparatorMetrics.minimumTarget
                    )
                    .background(PosterPalette.paperWhite.opacity(0.94), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(PosterPalette.actionBlue.opacity(0.24), lineWidth: 1)
                    }
            }
            .buttonStyle(PosterPressStyle())
            .disabled(!cadenceIsAllowed || cadenceTask != nil)
            .opacity(cadenceIsAllowed ? 1 : 0.56)
            .accessibilityIdentifier("result.blink-cadence")
            .accessibilityLabel("慢速闪看一轮")
            .accessibilityValue(cadenceTask == nil ? "已停止" : "正在进行")
            .accessibilityHint(cadenceAccessibilityHint)
        }
    }

    private var holdControl: some View {
        HStack(spacing: PosterSpacing.sm) {
            Image(systemName: visibleFrame == .original ? "camera.fill" : "hand.point.up.left.fill")
                .accessibilityHidden(true)

            Text(holdControlTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(PosterTypography.label)
        .foregroundStyle(PosterPalette.paperWhite)
        .padding(.horizontal, PosterSpacing.md)
        .frame(minHeight: TemporalBlinkComparatorMetrics.minimumTarget)
        .background(PosterPalette.ink.opacity(0.78), in: Capsule())
        .contentShape(Capsule())
        .gesture(holdGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("result.blink-hold")
        .accessibilityLabel("原片与目标时间眨眼对照")
        .accessibilityValue(frameAccessibilityValue)
        .accessibilityHint("双击明确切换；触摸时也可按住查看原片，松开返回")
        .accessibilityAction {
            toggleLockedFrame()
        }
        .accessibilityAction(named: Text("显示原片")) {
            lock(to: .original)
        }
        .accessibilityAction(named: Text("显示目标时间")) {
            lock(to: .generated)
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isHoldingOriginal) { _, isHolding, _ in
                if hasBothFrames {
                    isHolding = true
                }
            }
            .onChanged { _ in
                cancelCadence()
            }
    }

    private var holdControlTitle: String {
        if isHoldingOriginal, lockedFrame == .generated {
            return "松开 · 回到目标"
        }
        if lockedFrame == .original {
            return "当前原片 · 双击看目标"
        }
        return "按住 · 看原片"
    }

    private var frameAccessibilityValue: String {
        switch visibleFrame {
        case .original:
            "当前显示原片 NOW"
        case .generated:
            "当前显示目标时间 (targetTime.compactLabel)"
        }
    }

    private var cadenceAccessibilityHint: String {
        if reduceMotion {
            return "已开启减少动态效果，慢速节奏已停用；可使用明确切换"
        }
        if dimFlashingLights {
            return "已开启调暗闪烁灯光，慢速节奏已停用；可使用明确切换"
        }
        return "双击后以安全慢速完整切换一轮，不会循环"
    }

    private func comparisonImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }

    private func toggleLockedFrame() {
        guard hasBothFrames else { return }
        cancelCadence()
        lock(to: engine.toggled(lockedFrame))
    }

    private func lock(to frame: TemporalBlinkFrame) {
        guard hasBothFrames else { return }
        cancelCadence()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            lockedFrame = frame
        }
    }

    private func startCadence() {
        guard cadenceIsAllowed else { return }
        cancelCadence()
        let plan = engine.blinkPlan(
            startingFrom: lockedFrame,
            reduceMotion: reduceMotion,
            dimFlashingLights: dimFlashingLights
        )
        guard !plan.isEmpty else { return }

        cadenceTask = Task { @MainActor in
            for step in plan {
                if step.delay > .zero {
                    try? await Task.sleep(for: step.delay)
                }
                guard !Task.isCancelled else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    cadenceFrame = step.frame
                }
            }
            cadenceFrame = nil
            cadenceTask = nil
        }
    }

    private func cancelCadence() {
        cadenceTask?.cancel()
        cadenceTask = nil
        cadenceFrame = nil
    }
}

#Preview("眨眼对照") {
    TemporalBlinkComparator(
        originalImage: UIImage(systemName: "photo"),
        generatedImage: UIImage(systemName: "photo.fill"),
        targetTime: TimePosition(normalized: 0.45)
    )
    .frame(width: 320, height: 420)
    .padding()
    .background(PosterPalette.canvas)
}

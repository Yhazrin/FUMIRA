import SwiftUI
import UIKit

struct ResultView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTiltTimeActive = false
    @State private var tiltBaselineRoll: Double?
    @State private var tiltLastSampleTime: TimeInterval?
    @State private var tiltLastHapticYears: Double?
    @State private var tiltStructureTime: TimePosition?
    @State private var selectedFutureForkIndex = 0
    @State private var futureForkShakeFeedbackTrigger: Int?
    @State private var showsInterpretationEvidence = false

    private var generatedTime: TimePosition {
        model.generatedFrame?.time ?? model.generationTargetTime
    }

    private var isBrowseTimeGenerated: Bool {
        ResultBrowseFrameIdentity.isGenerated(
            browsedTime: structureTime,
            generatedTime: generatedTime
        )
    }

    /// High-frequency device tilt may move the rail continuously, but it must
    /// not rebuild the rest of the page thirty times per second. Text, actions,
    /// and future branches commit once when tilt browsing stops.
    private var structureTime: TimePosition {
        tiltStructureTime ?? model.selectedTime
    }

    private var resultTitle: String {
        generatedTime == .now ? "此刻的回信" : "\(generatedTime.compactLabel)的回信"
    }

    private var frameProvenanceText: String {
        if isBrowseTimeGenerated {
            if let forkTitle = model.generatedFrame?.futureForkTitle {
                return "已生成 · \(generatedTime.compactLabel) · \(forkTitle)"
            }
            return "已生成 · \(generatedTime.compactLabel)"
        }
        return "浏览 \(structureTime.compactLabel) · 当前照片 \(generatedTime.compactLabel)"
    }

    private var generatedImage: UIImage? {
        model.decodedGeneratedImage
            ?? model.generatedFrame?.imageData.flatMap(UIImage.init(data:))
    }

    private var blowGust: CGFloat {
        #if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["FUMIRA_AUDIT_BLOW_GUST"],
           let value = Double(rawValue) {
            return FUMIRASpatialMotion.clamp(CGFloat(value))
        }
        #endif
        return CGFloat(model.blowReveal.snapshot.gust)
    }

    private var futureForkResult: TemporalFutureForkResult {
        TemporalFutureForkEngine.resolve(
            understanding: model.sceneUnderstanding,
            target: generatedTime
        )
    }

    private var futureForkBranches: [TemporalFutureForkBranch] {
        futureForkResult.branches
    }

    private var canOfferFutureForks: Bool {
        generatedTime.offsetDays > 0
            && isBrowseTimeGenerated
            && futureForkBranches.count >= 2
    }

    /// Read-only context for the current browse position. The witness layer
    /// explains the selected time without becoming another time control or
    /// changing which frame was generated.
    private var interpretationTrace: TemporalInterpretationTrace {
        TemporalInterpretationTrace.resolve(
            story: model.temporalStory,
            understanding: model.sceneUnderstanding,
            at: structureTime
        )
    }

    private var displayedNarrative: String {
        guard let narrative = model.temporalStory?.narrative(for: structureTime) else {
            return "同一处现实，抵达另一个时间。"
        }
        return StoryCopyPolicy.removingRepeatedTimePrefix(
            from: narrative,
            time: structureTime
        )
    }

    /// The generated result owns its own geometry. Never force it back into the
    /// camera-source ratio because relay providers may return a corrected size.
    private var photoAspectRatio: CGFloat {
        if let generatedImage, generatedImage.size.height > 0 {
            return generatedImage.size.width / generatedImage.size.height
        }
        if let ratio = model.generatedPhoto?.displayAspectRatio, ratio > 0 {
            return CGFloat(ratio)
        }
        if let ratio = model.capturedPhoto?.displayAspectRatio, ratio > 0 {
            return CGFloat(ratio)
        }
        return 3.0 / 4.0
    }

    var body: some View {
        resultPage
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
            if model.temporalShake.isMonitoring,
               let service = model.temporalShakeResponderService {
                TemporalShakeResponderBridge(service: service)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            alignFutureForkSelection()
            #if DEBUG
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_RESULT_REVEAL"] == "1" {
                model.completeResultReveal()
            }
            if let rawProgress = ProcessInfo.processInfo.environment[
                "FUMIRA_AUDIT_RESULT_REVEAL_PROGRESS"
            ],
               let progress = Double(rawProgress) {
                model.updateResultRevealProgress(CGFloat(progress))
            }
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_REALITY_ALIGNMENT"] == "1" {
                model.completeResultReveal()
                presentRealityComparison(animated: false)
            }
            #endif
            if model.resultRevealProgress < 0.999 {
                model.blowReveal.activate()
            }
        }
        .onChange(of: model.blowReveal.snapshot) { _, snapshot in
            model.updateResultRevealProgress(CGFloat(snapshot.revealProgress))
        }
        .onChange(of: model.captureMotion.roll) { _, roll in
            advanceTiltTime(using: roll)
        }
        .onChange(of: model.temporalShake.latestEvent) { previous, event in
            guard event != nil, event != previous else { return }
            advanceFutureForkFromShake()
        }
        .onChange(of: model.isRealityAlignmentPresented) { _, isPresented in
            if isPresented {
                stopTiltTime()
            }
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                stopTiltTime()
            }
        }
        .onDisappear {
            stopTiltTime()
            model.blowReveal.deactivate()
            model.temporalShake.deactivate()
        }
    }

    private var resultPage: some View {
        PosterScreenContainer(background: .clear) {
            VStack(alignment: .leading, spacing: PosterSpacing.lg) {
                ResultPageHeading(
                    title: resultTitle,
                    interpretation: "一种可能的时间解释"
                )

                ZStack {
                    HeroPhotoSlot(
                        owner: .result,
                        aspectRatio: photoAspectRatio,
                        maximumHeight: ResultLayoutGeometry.accessiblePhotoMaximumHeight,
                        cornerRadius: PosterRadius.photoPaper
                    )

                    TemporalBlowRevealSurface(
                        original: model.decodedCapturedImage,
                        progress: model.resultRevealProgress,
                        gust: blowGust,
                        reduceMotion: reduceMotion,
                        targetLabel: generatedTime.compactLabel,
                        handwrittenTitle: model.temporalStory?.title
                            ?? "风把时间吹开"
                    )

                    if model.isRealityAlignmentPresented {
                        RealityComparisonSurface(
                            original: model.decodedCapturedImage,
                            generated: generatedImage,
                            target: generatedTime,
                            close: dismissRealityComparison
                        )
                        .transition(.opacity)
                    }
                }

                if model.resultRevealProgress < 0.999 {
                    BlowRevealPrompt(
                        target: generatedTime,
                        progress: model.resultRevealProgress
                    ) {
                        completeBlowReveal()
                    }
                } else {
                    resultActionDock
                }

                narrativeSection

                TimeRail(
                    value: model.selectedTime.normalized,
                    isExternalValueDirectDriven: isTiltTimeActive,
                    onDetent: model.playTimeDetent
                ) { normalized in
                    stopTiltTime()
                    model.updateTime(normalized: normalized)
                }

                if canOfferFutureForks {
                    futureForkSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultActionDock: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            if !isBrowseTimeGenerated {
                generateBrowsedFrameButton
            }

            saveButton

            HStack(spacing: PosterSpacing.sm) {
                Spacer(minLength: PosterSpacing.sm)

                compactAction(
                    title: "对准现实",
                    systemImage: "viewfinder"
                ) {
                    presentRealityComparison()
                }
                .opacity(canPresentRealityComparison ? 1 : 0)
                .allowsHitTesting(canPresentRealityComparison)
                .accessibilityHidden(!canPresentRealityComparison)

                compactTiltTimeAction
                    .opacity(canOfferTiltTime ? 1 : 0)
                    .allowsHitTesting(canOfferTiltTime)
                    .accessibilityHidden(!canOfferTiltTime)

                compactMoreActionsMenu
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.action-dock")
    }

    private var canPresentRealityComparison: Bool {
        model.resultRevealProgress >= 0.999
            && !model.isRealityAlignmentPresented
    }

    private var saveButton: some View {
        TemporalSaveCapsule(
            title: "保存海报",
            revealProgress: model.resultRevealProgress,
            reduceMotion: reduceMotion
        ) {
            model.openShare()
        }
        .posterSensoryFeedback(
            trigger: model.shareFeedbackMessage == "已保存到相册",
            .success
        )
    }

    private func compactAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .frame(
                    width: PosterControlMetric.compactDiameter,
                    height: PosterControlMetric.compactDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel(title)
    }

    private var compactTiltTimeAction: some View {
        Button(action: toggleTiltTime) {
            Image(systemName: isTiltTimeActive ? "pause.circle" : "gyroscope")
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    isTiltTimeActive
                        ? PosterPalette.paperWhite
                        : PosterPalette.actionBlueDeep
                )
                .frame(
                    width: PosterControlMetric.compactDiameter,
                    height: PosterControlMetric.compactDiameter
                )
                .background(
                    isTiltTimeActive
                        ? PosterPalette.actionBlueDeep
                        : Color.clear,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(PosterPressStyle())
        .disabled(model.isPreparingBrowsedTimeGeneration)
        .posterSensoryFeedback(trigger: isTiltTimeActive, .selection)
        .accessibilityIdentifier("result.tilt-time")
        .accessibilityLabel(isTiltTimeActive ? "停止倾斜穿越" : "开启倾斜穿越")
        .accessibilityValue(isTiltTimeActive ? "已开启" : "已关闭")
        .accessibilityHint(
            isTiltTimeActive
                ? "停止使用设备倾斜浏览时间"
                : "开启后，向左倾斜浏览过去，向右倾斜浏览未来，回正时停止"
        )
        .accessibilityAddTraits(isTiltTimeActive ? .isSelected : [])
    }

    private var compactMoreActionsMenu: some View {
        Menu {
            Button {
                Task { await model.regenerateResult() }
            } label: {
                Label("重新生成", systemImage: "sparkles")
            }

            if model.canUndoGeneration {
                Button {
                    model.undoLastGeneration()
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
            }

            Button {
                model.openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive) {
                model.retake()
            } label: {
                Label("重拍", systemImage: "camera.rotate")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(PosterPalette.mutedInk)
                .frame(
                    width: PosterControlMetric.compactDiameter,
                    height: PosterControlMetric.compactDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityIdentifier("result.more-actions")
        .accessibilityLabel("更多")
        .accessibilityHint("重新生成、撤销、设置和重拍")
    }

    private var generateBrowsedFrameButton: some View {
        PosterCapsuleButton(
            title: model.isPreparingBrowsedTimeGeneration ? "正在对齐这一帧…" : "生成这一帧",
            accessibilityHint: "使用当前浏览的 \(model.selectedTime.compactLabel) 重新生成照片"
        ) {
            stopTiltTime()
            Task { await model.generateAtStoryPreviewTime() }
        }
        .disabled(model.isPreparingBrowsedTimeGeneration)
        .accessibilityIdentifier("result.generate-browsed-frame")
    }

    private var narrativeSection: some View {
        let trace = interpretationTrace

        return VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            Text(displayedNarrative)
                .font(PosterTypography.supporting)
                .foregroundStyle(PosterPalette.mutedInk)
                .lineLimit(showsInterpretationEvidence ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            DisclosureGroup(isExpanded: $showsInterpretationEvidence) {
                TemporalWitnessRibbon(trace: trace)
                    .padding(.top, PosterSpacing.sm)
            } label: {
                Text("画面线索")
                    .font(PosterTypography.label)
                    .foregroundStyle(PosterPalette.mutedInk)
                    .frame(minHeight: PosterControlMetric.minimumTouchTarget, alignment: .leading)
            }
            .tint(PosterPalette.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("result.temporal-interpretation")
        .accessibilityValue(frameProvenanceText)
    }

    private var selectedFutureFork: TemporalFutureForkBranch? {
        guard !futureForkBranches.isEmpty else { return nil }
        let index = min(max(selectedFutureForkIndex, 0), futureForkBranches.count - 1)
        return futureForkBranches[index]
    }

    private var futureForkPresentationItems: [TemporalFutureForkView.PresentationItem] {
        futureForkBranches.map { branch in
            TemporalFutureForkView.PresentationItem(
                id: branch.id,
                title: branch.title,
                rationale: branch.rationale,
                evidence: branch.evidence
                    .map(\.observedEvidence)
                    .joined(separator: " · ")
            )
        }
    }

    private var futureForkSection: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            TemporalFutureForkView(
                items: futureForkPresentationItems,
                selectedIndex: selectedFutureForkIndex,
                reduceMotion: reduceMotion,
                shakeFeedbackTrigger: futureForkShakeFeedbackTrigger
            ) { index in
                selectedFutureForkIndex = index
                futureForkShakeFeedbackTrigger = nil
                model.playFutureForkDetent()
            }

            if let selectedFutureFork {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PosterSpacing.md) {
                        futureForkAdvanceAction

                        Spacer(minLength: PosterSpacing.sm)

                        futureForkGenerateAction(selectedFutureFork)
                    }

                    VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                        futureForkGenerateAction(selectedFutureFork)
                        futureForkAdvanceAction
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var futureForkAdvanceAction: some View {
        Button {
            model.temporalShake.requestFallbackAdvance()
        } label: {
            Label(
                "下一种",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(PosterTypography.label)
            .foregroundStyle(PosterPalette.mutedInk)
            .frame(minHeight: PosterControlMetric.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel("换一种可能")
        .accessibilityIdentifier("result.future-fork.advance")
    }

    private func futureForkGenerateAction(
        _ branch: TemporalFutureForkBranch
    ) -> some View {
        let isCurrent = model.generatedFrame?.futureForkID == branch.id

        return Button {
            Task {
                await model.generateFutureFork(branch)
            }
        } label: {
            Text(isCurrent ? "已经显影" : "显影这一可能")
                .font(PosterTypography.label)
                .foregroundStyle(
                    isCurrent
                        ? PosterPalette.mutedInk
                        : PosterPalette.paperWhite
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, PosterSpacing.md)
                .frame(minHeight: PosterControlMetric.minimumTouchTarget)
                .background(
                    isCurrent
                        ? PosterPalette.cardLight
                        : PosterPalette.actionBlue,
                    in: Capsule()
                )
                .overlay {
                    if isCurrent {
                        Capsule()
                            .stroke(PosterPalette.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(PosterPressStyle())
        .disabled(isCurrent)
        .accessibilityHint(
            "保持 \(generatedTime.compactLabel) 不变，从原始照片生成所选未来分支"
        )
        .accessibilityIdentifier("result.future-fork.generate")
    }

    private func alignFutureForkSelection() {
        guard !futureForkBranches.isEmpty else {
            selectedFutureForkIndex = 0
            futureForkShakeFeedbackTrigger = nil
            return
        }
        if let currentID = model.generatedFrame?.futureForkID,
           let index = futureForkBranches.firstIndex(where: { $0.id == currentID }) {
            selectedFutureForkIndex = index
        } else {
            selectedFutureForkIndex = 0
        }
        futureForkShakeFeedbackTrigger = nil
    }

    private func advanceFutureForkFromShake() {
        guard canOfferFutureForks, futureForkBranches.count > 1 else { return }
        let current = min(max(selectedFutureForkIndex, 0), futureForkBranches.count - 1)
        selectedFutureForkIndex = (current + 1) % futureForkBranches.count
        futureForkShakeFeedbackTrigger = (futureForkShakeFeedbackTrigger ?? 0) + 1
        model.playFutureForkDetent()
    }

    private func toggleTiltTime() {
        if isTiltTimeActive {
            stopTiltTime()
            return
        }

        guard canOfferTiltTime else { return }

        isTiltTimeActive = true
        tiltStructureTime = model.selectedTime
        // The first sensor sample after opt-in establishes a real baseline.
        // Reusing the observable's initial zero can otherwise jump time on
        // hardware whose current attitude has not been published yet.
        tiltBaselineRoll = nil
        tiltLastSampleTime = nil
        tiltLastHapticYears = model.selectedTime.offsetYears
    }

    private func stopTiltTime() {
        isTiltTimeActive = false
        tiltStructureTime = nil
        tiltBaselineRoll = nil
        tiltLastSampleTime = nil
        tiltLastHapticYears = nil
    }

    private func advanceTiltTime(using currentRoll: Double) {
        guard
            isTiltTimeActive,
            canOfferTiltTime,
            !model.isPreparingBrowsedTimeGeneration,
            currentRoll.isFinite
        else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard let baselineRoll = tiltBaselineRoll,
              let lastSampleTime = tiltLastSampleTime else {
            tiltBaselineRoll = currentRoll
            tiltLastSampleTime = now
            return
        }
        tiltLastSampleTime = now

        let next = TiltTimeNavigator.standard.advance(
            model.selectedTime,
            rollRadians: signedAngularDelta(currentRoll, baselineRoll),
            frameDelta: now - lastSampleTime
        )
        guard next != model.selectedTime else { return }

        let previousYears = tiltLastHapticYears ?? model.selectedTime.offsetYears
        model.updateTime(normalized: next.normalized)
        if WaveTimeHapticCrossing.shouldTick(
            previousYears: previousYears,
            currentYears: next.offsetYears
        ) {
            model.playTimeDetent(
                WaveTimeHapticCrossing.crossedNow(
                    previousYears: previousYears,
                    currentYears: next.offsetYears
                ) ? .now : .decade
            )
        }
        tiltLastHapticYears = next.offsetYears
    }

    private var canOfferTiltTime: Bool {
        !reduceMotion
            && model.resultRevealProgress >= 0.999
            && model.captureMotion.isActive
            && !model.isRealityAlignmentPresented
    }

    private func signedAngularDelta(_ current: Double, _ baseline: Double) -> Double {
        var delta = current - baseline
        while delta > .pi { delta -= .pi * 2 }
        while delta < -.pi { delta += .pi * 2 }
        return delta
    }

    /// Present original ↔ generated comparison in the same bounded hero frame.
    private func presentRealityComparison(animated: Bool = true) {
        let apply = {
            model.isRealityAlignmentPresented = true
        }
        if animated {
            withAnimation(
                reduceMotion
                    ? .linear(duration: PosterMotion.reduced)
                    : PosterMotion.resultPanelSettle
            ) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func dismissRealityComparison() {
        withAnimation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : PosterMotion.resultPanelSettle
        ) {
            model.isRealityAlignmentPresented = false
        }
    }

    private func completeBlowReveal() {
        withAnimation(
            reduceMotion
                ? .linear(duration: PosterMotion.reduced)
                : PosterMotion.timeReveal
        ) {
            model.completeResultReveal()
        }
    }

}

enum ResultBrowseFrameIdentity {
    static func isGenerated(
        browsedTime: TimePosition,
        generatedTime: TimePosition
    ) -> Bool {
        browsedTime.hasSameExactTimeIdentity(asOffsetDays: generatedTime.offsetDays)
    }
}

private struct ResultPageHeading: View {
    let title: String
    let interpretation: String

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            Text(interpretation)
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.mutedInk)

            Text(title)
                .font(PosterTypography.screenTitle)
                .foregroundStyle(PosterPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct BlowRevealPrompt: View {
    let target: TimePosition
    let progress: CGFloat
    let complete: () -> Void

    var body: some View {
        let clampedProgress = FUMIRASpatialMotion.clamp(progress)

        HStack(spacing: PosterSpacing.sm) {
            Label("吹一口气", systemImage: "wind")
                .font(PosterTypography.label)
                .foregroundStyle(PosterPalette.actionBlueDeep)

            Spacer(minLength: PosterSpacing.xs)

            Button(action: complete) {
                Text("直接显影")
                    .font(PosterTypography.label)
                    .foregroundStyle(PosterPalette.ink)
                    .padding(.horizontal, PosterSpacing.md)
                    .frame(minHeight: PosterControlMetric.minimumTouchTarget)
                    .background(PosterPalette.bellYellow, in: Capsule())
            }
            .buttonStyle(PosterPressStyle())
            .accessibilityIdentifier("result.reveal-now")
            .accessibilityHint("不使用麦克风，直接显示\(target.compactLabel)的照片")
        }
        .padding(.leading, PosterSpacing.md)
        .padding(.trailing, PosterSpacing.xs)
        .padding(.vertical, PosterSpacing.xs)
        .background(PosterPalette.paperWhite, in: Capsule())
        .overlay {
            Capsule()
                .stroke(PosterPalette.line, lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("照片尚未完全显影")
        .accessibilityValue("\(Int(clampedProgress * 100))%")
        // This prompt lives inside a bounded photo frame. Keep it legible at
        // accessibility sizes without letting it cover the photo completely.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// Inline original ↔ generated comparison on the hero photo frame.
/// Presented by sliding the result panel down — never as a separate page.
private struct RealityComparisonSurface: View {
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
                RoundedRectangle(cornerRadius: PosterRadius.photoPaper, style: .continuous)
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
                    .foregroundStyle(PosterPalette.actionBlueDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PosterPalette.paperWhite.opacity(0.94), in: Capsule())
                Spacer()
                Text(target.compactLabel)
                    .foregroundStyle(PosterPalette.paperWhite)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PosterPalette.actionBlue, in: Capsule())
            }
            .font(PosterTypography.caption.weight(.semibold))
            .padding(.horizontal, PosterSpacing.md)
            .padding(.top, PosterSpacing.lg + CameraChromeMetrics.controlDiameter)
            .allowsHitTesting(false)
            .zIndex(4)

            PosterGlassCard(cornerRadius: PosterRadius.card) {
                Text("拖动，看时间差")
                    .font(PosterTypography.cardTitle)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PosterSpacing.md)
            .padding(.bottom, PosterSpacing.md)
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
        HStack(spacing: PosterSpacing.sm) {
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
        .padding(.horizontal, PosterSpacing.md)
        .padding(.top, PosterSpacing.sm)
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
                .font(PosterTypography.label)
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .frame(
                    width: CameraChromeMetrics.controlDiameter,
                    height: CameraChromeMetrics.controlDiameter
                )
                .background(PosterPalette.paperWhite.opacity(0.94), in: Circle())
                .overlay {
                    Circle()
                        .stroke(PosterPalette.actionBlue.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(accessibilityLabel)
    }

    private func boundaryHandle(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(PosterPalette.paperWhite.opacity(0.92))
                .frame(width: 3, height: height)
                .shadow(color: PosterPalette.actionBlue.opacity(0.22), radius: 6)

            Capsule(style: .continuous)
                .fill(PosterPalette.paperWhite)
                .frame(width: 34, height: 56)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(PosterPalette.actionBlue.opacity(0.28), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(PosterTypography.caption)
                        .foregroundStyle(PosterPalette.actionBlueDeep)
                }
                .shadow(color: PosterPalette.actionBlue.opacity(0.18), radius: 10, y: 3)
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
            PosterPalette.skySoft
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
            let color = PosterPalette.paperWhite.opacity(0.38)
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

enum ResultLayoutGeometry {
    static let accessiblePhotoMaximumHeight: CGFloat = 520
    private static let headerHeight: CGFloat = 58
    private static let preferredPanelHeight: CGFloat = 390
    private static let minimumVisiblePanelHeight: CGFloat = 116

    struct Layout: Equatable {
        var viewportWidth: CGFloat
        var photoSize: CGSize
        var photoTop: CGFloat
        var panelTop: CGFloat
        var panelHeight: CGFloat
        var safeAreaBottom: CGFloat
        var maximumPanelPull: CGFloat
    }

    struct PrimaryActionLayout: Equatable {
        var isStacked: Bool
        var buttonWidth: CGFloat
        var spacing: CGFloat
    }

    static func layout(
        in container: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        aspectRatio: CGFloat
    ) -> Layout {
        let viewportWidth = max(container.width, 1)
        // Root is full-bleed; consume the reported top inset exactly once so the
        // header clears the status region without a second reserved band.
        let photoTop = safeAreaTop + headerHeight
        let photoSize = photoSize(
            in: container,
            safeAreaTop: photoTop,
            aspectRatio: aspectRatio
        )
        let preferredTop = container.height - preferredPanelHeight - safeAreaBottom
        let photoDrivenTop = photoTop + photoSize.height * 0.62
        let maximumTop = max(container.height - minimumVisiblePanelHeight - safeAreaBottom, 0)
        let panelTop = min(
            max(max(preferredTop, photoDrivenTop), photoTop + 120),
            maximumTop
        )
        let panelHeight = max(container.height - panelTop, minimumVisiblePanelHeight)
        let photoBottom = photoTop + photoSize.height
        let desiredReveal = max(photoBottom - panelTop + PosterSpacing.md, 96)
        let maximumPanelPull = min(
            desiredReveal,
            max(panelHeight - minimumVisiblePanelHeight - safeAreaBottom, 0)
        )

        return Layout(
            viewportWidth: viewportWidth,
            photoSize: photoSize,
            photoTop: photoTop,
            panelTop: panelTop,
            panelHeight: panelHeight,
            safeAreaBottom: max(safeAreaBottom, 0),
            maximumPanelPull: maximumPanelPull
        )
    }

    static func layout(
        in container: CGSize,
        safeAreaTop: CGFloat,
        aspectRatio: CGFloat
    ) -> Layout {
        layout(
            in: container,
            safeAreaTop: safeAreaTop,
            safeAreaBottom: 0,
            aspectRatio: aspectRatio
        )
    }

    static func photoSize(
        in container: CGSize,
        safeAreaTop: CGFloat,
        aspectRatio: CGFloat
    ) -> CGSize {
        let ratio = max(aspectRatio, 0.01)
        let availableWidth = max(container.width, 1)
        let maximumHeight = max(container.height - safeAreaTop - PosterSpacing.sm, 1)
        let widthDrivenHeight = availableWidth / ratio

        if widthDrivenHeight <= maximumHeight {
            return CGSize(width: availableWidth, height: widthDrivenHeight)
        }
        return CGSize(width: maximumHeight * ratio, height: maximumHeight)
    }

    static func contentWidth(in viewportWidth: CGFloat) -> CGFloat {
        max(viewportWidth - PosterSpacing.md * 2, 1)
    }

    static func primaryActionLayout(in contentWidth: CGFloat) -> PrimaryActionLayout {
        let width = max(contentWidth, 1)
        let spacing = PosterSpacing.sm
        if width < 330 {
            return PrimaryActionLayout(
                isStacked: true,
                buttonWidth: width,
                spacing: spacing
            )
        }
        return PrimaryActionLayout(
            isStacked: false,
            buttonWidth: max((width - spacing) / 2, 1),
            spacing: spacing
        )
    }
}

private enum ResultPanelDetent: Equatable {
    case controls
    case photo
}

private struct ResultTextAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
                .frame(maxWidth: .infinity, minHeight: PosterControlMetric.minimumTouchTarget)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, PosterSpacing.xs)
                .background(PosterPalette.cardActive)
                .clipShape(RoundedRectangle(cornerRadius: PosterRadius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel(title)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            ResultView(model: PreviewFixtures.model(phase: .result), namespace: namespace)
        }
    }
    return PreviewWrapper()
}

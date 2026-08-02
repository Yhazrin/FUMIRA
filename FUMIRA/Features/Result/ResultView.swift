import SwiftUI
import UIKit

struct ResultView: View {
    let model: AppModel
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = ResultTiltTimeController()
    @State private var selectedFutureForkIndex = 0
    @State private var futureForkShakeFeedbackTrigger: Int?
    @State private var showsInterpretationEvidence = false
    @State private var showsDiorama = false

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
        tilt.structureTime ?? model.selectedTime
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
        model.experimental.isEnabled(.futureFork)
            && generatedTime.offsetDays > 0
            && isBrowseTimeGenerated
            && futureForkBranches.count >= 2
    }

    /// Blow-to-reveal is an experiment. When it is off the photo is simply
    /// present and nothing gates the action dock.
    private var isBlowRevealEnabled: Bool {
        model.experimental.isEnabled(.blowReveal)
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
        .sheet(isPresented: $showsDiorama) {
            DioramaView(model: model)
                .interactiveDismissDisabled(false)
        }
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
                guard isBlowRevealEnabled else {
                    model.completeResultReveal()
                    return
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard model.resultRevealProgress < 0.999 else { return }
                    model.blowReveal.activate()
                }
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
            VStack(alignment: .leading, spacing: ClaySpacing.xxl) {
                ResultPageHeading(
                    title: resultTitle,
                    interpretation: "一种可能的时间解释"
                )

                ZStack {
                    HeroPhotoSlot(
                        owner: .result,
                        aspectRatio: photoAspectRatio,
                        maximumHeight: ResultLayoutGeometry.accessiblePhotoMaximumHeight,
                        cornerRadius: ClayShape.lg
                    )

                    if isBlowRevealEnabled {
                        TemporalBlowRevealSurface(
                            original: model.decodedCapturedImage,
                            progress: model.resultRevealProgress,
                            gust: blowGust,
                            reduceMotion: reduceMotion,
                            targetLabel: generatedTime.compactLabel,
                            handwrittenTitle: model.temporalStory?.title
                                ?? "风把时间吹开"
                        )
                    }

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

                if isBlowRevealEnabled, model.resultRevealProgress < 0.999 {
                    BlowRevealPrompt(
                        target: generatedTime,
                        progress: model.resultRevealProgress
                    ) {
                        completeBlowReveal()
                    }
                } else {
                    actionDock
                }

                ResultNarrativeSection(
                    narrative: displayedNarrative,
                    trace: interpretationTrace,
                    provenance: frameProvenanceText,
                    isEvidenceExpanded: $showsInterpretationEvidence
                )

                TimeRail(
                    value: model.selectedTime.normalized,
                    isExternalValueDirectDriven: tilt.isActive,
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

    private var actionDock: some View {
        ResultActionDock(
            isBrowseTimeGenerated: isBrowseTimeGenerated,
            isPreparingGeneration: model.isPreparingBrowsedTimeGeneration,
            canPresentComparison: canPresentRealityComparison,
            canOfferTilt: canOfferTiltTime,
            isTiltActive: tilt.isActive,
            canUndo: model.canUndoGeneration,
            browseLabel: model.selectedTime.compactLabel,
            revealProgress: model.resultRevealProgress,
            reduceMotion: reduceMotion,
            isDioramaEnabled: model.experimental.isEnabled(.diorama),
            didSaveToLibrary: model.shareFeedbackMessage == "已保存到相册",
            onGenerateBrowsedFrame: {
                stopTiltTime()
                Task { await model.generateAtStoryPreviewTime() }
            },
            onSave: { model.openShare() },
            onPresentComparison: { presentRealityComparison() },
            onToggleTilt: toggleTiltTime,
            onRegenerate: { Task { await model.regenerateResult() } },
            onUndo: { model.undoLastGeneration() },
            onOpenSettings: { model.openSettings() },
            onRetake: { model.retake() },
            onShowDiorama: { showsDiorama = true }
        )
    }

    private var canPresentRealityComparison: Bool {
        model.resultRevealProgress >= 0.999
            && !model.isRealityAlignmentPresented
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
        ResultFutureForkSection(
            items: futureForkPresentationItems,
            branches: futureForkBranches,
            selectedIndex: selectedFutureForkIndex,
            currentForkID: model.generatedFrame?.futureForkID,
            targetLabel: generatedTime.compactLabel,
            reduceMotion: reduceMotion,
            shakeFeedbackTrigger: futureForkShakeFeedbackTrigger,
            isShakeEnabled: model.experimental.isEnabled(.shakeToFork),
            onSelect: { index in
                selectedFutureForkIndex = index
                futureForkShakeFeedbackTrigger = nil
                model.playFutureForkDetent()
            },
            onRequestAdvance: {
                model.temporalShake.requestFallbackAdvance()
            },
            onGenerate: { branch in
                Task { await model.generateFutureFork(branch) }
            }
        )
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
        if tilt.isActive {
            tilt.stop()
            return
        }
        guard canOfferTiltTime else { return }
        tilt.start(from: model.selectedTime)
    }

    private func stopTiltTime() {
        tilt.stop()
    }

    private func advanceTiltTime(using currentRoll: Double) {
        guard canOfferTiltTime, !model.isPreparingBrowsedTimeGeneration else {
            return
        }
        guard let advance = tilt.advance(
            from: model.selectedTime,
            roll: currentRoll
        ) else {
            return
        }

        model.updateTime(normalized: advance.time.normalized)
        if let detent = advance.detent {
            model.playTimeDetent(detent)
        }
    }

    private var canOfferTiltTime: Bool {
        !reduceMotion
            && model.resultRevealProgress >= 0.999
            && model.captureMotion.isActive
            && !model.isRealityAlignmentPresented
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
        VStack(alignment: .leading, spacing: ClaySpacing.xxs) {
            Text(interpretation)
                .font(ClayTypography.labelSmall)
                .foregroundStyle(ClayPalette.textMuted)

            Text(title)
                .font(ClayTypography.displaySmall)
                .foregroundStyle(ClayPalette.charcoal)
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

        HStack(spacing: ClaySpacing.sm) {
            Label("吹一口气", systemImage: "wind")
                .font(ClayTypography.label)
                .foregroundStyle(ClayPalette.orangeRim)

            Spacer(minLength: ClaySpacing.xxs)

            Button(action: complete) {
                Text("直接显影")
                    .font(ClayTypography.label)
                    .foregroundStyle(ClayPalette.charcoal)
                    .padding(.horizontal, ClaySpacing.lg)
                    .frame(minHeight: ClaySpacing.minTapTarget)
                    .background(ClayPalette.yellow, in: Capsule())
            }
            .buttonStyle(PosterPressStyle())
            .accessibilityIdentifier("result.reveal-now")
            .accessibilityHint("不使用麦克风，直接显示\(target.compactLabel)的照片")
        }
        .padding(.leading, ClaySpacing.lg)
        .padding(.trailing, ClaySpacing.xxs)
        .padding(.vertical, ClaySpacing.xxs)
        .background(ClayPalette.warmWhite, in: Capsule())
        .overlay {
            Capsule()
                .stroke(ClayPalette.warmWhiteRim, lineWidth: 1)
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
        let desiredReveal = max(photoBottom - panelTop + ClaySpacing.lg, 96)
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
        let maximumHeight = max(container.height - safeAreaTop - ClaySpacing.sm, 1)
        let widthDrivenHeight = availableWidth / ratio

        if widthDrivenHeight <= maximumHeight {
            return CGSize(width: availableWidth, height: widthDrivenHeight)
        }
        return CGSize(width: maximumHeight * ratio, height: maximumHeight)
    }

    static func contentWidth(in viewportWidth: CGFloat) -> CGFloat {
        max(viewportWidth - ClaySpacing.lg * 2, 1)
    }

    static func primaryActionLayout(in contentWidth: CGFloat) -> PrimaryActionLayout {
        let width = max(contentWidth, 1)
        let spacing = ClaySpacing.sm
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
                .foregroundStyle(ClayPalette.orangeRim)
                .frame(maxWidth: .infinity, minHeight: ClaySpacing.minTapTarget)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, ClaySpacing.xxs)
                .background(ClayPalette.orange)
                .clipShape(RoundedRectangle(cornerRadius: ClayShape.md, style: .continuous))
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

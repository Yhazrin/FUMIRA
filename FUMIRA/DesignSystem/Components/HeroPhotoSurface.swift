import SwiftUI
import UIKit

enum HeroPhotoMetrics {
    static let understandingMaximumHeight: CGFloat = 360
    static let understandingHorizontalInset = PosterSpacing.xl + PosterSpacing.md
    static let minimumInteractiveHeight = PosterSpacing.xl + PosterSpacing.md
    // A slight downward landing preserves the paper-drop direction without
    // stranding the sealed target beneath a large empty band.
    static let understandingVerticalOffset = PosterSpacing.xl

    static func understandingFrame(
        aspectRatio: CGFloat,
        in size: CGSize
    ) -> CGRect {
        let ratio = max(aspectRatio, 0.01)
        let availableWidth = max(size.width - understandingHorizontalInset * 2, 1)
        let height = min(understandingMaximumHeight, availableWidth / ratio)
        let width = height * ratio
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2 + understandingVerticalOffset,
            width: width,
            height: height
        )
    }
}

/// The reverse of a developing print is an intentional pause, not another
/// dashboard. The answer is local to the current capture session and remains
/// available while the pipeline advances through its silent stages.
private struct GenerationReflectionBack: View {
    let prompt: GenerationReflectionPrompt
    let selectedChoiceID: String?
    @Binding var note: String
    let isNoteCommitted: Bool
    let pipelinePhase: AppPhase
    let understandingProgress: Double
    let generationProgress: Double
    let onSelect: (GenerationReflectionPrompt.Choice) -> Void
    let onCommitNote: () -> Void

    private var selectedChoice: GenerationReflectionPrompt.Choice? {
        prompt.choices.first { $0.id == selectedChoiceID }
    }

    private var acknowledgement: String? {
        if prompt.interactionKind == .note {
            return isNoteCommitted ? prompt.noteAcknowledgement : nil
        }
        return selectedChoice?.acknowledgement
    }

    var body: some View {
        ZStack {
            PosterPalette.paperWhite

            VStack(alignment: .leading, spacing: PosterSpacing.md) {
                HStack(spacing: PosterSpacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("给时间的一句猜想")
                }
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.actionBlueDeep)

                Text(prompt.question)
                    .font(PosterTypography.cardTitle)
                    .foregroundStyle(PosterPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                interaction

                if let acknowledgement {
                    VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                        Text(acknowledgement)
                            .font(PosterTypography.caption)
                            .foregroundStyle(PosterPalette.mutedInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .accessibilityIdentifier("reality.reflection-confirmation")

                        GenerationPipelineTrace(
                            phase: pipelinePhase,
                            understandingProgress: understandingProgress,
                            generationProgress: generationProgress
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PosterSpacing.md)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reality.reflection-card")
        .accessibilityLabel("照片背面的时间提问")
        .accessibilityHint("选择一个答案，把自己的想法留在这一帧背面")
    }

    @ViewBuilder
    private var interaction: some View {
        switch prompt.interactionKind {
        case .choices:
            VStack(spacing: PosterSpacing.sm) {
                ForEach(prompt.choices) { choice in
                    choiceRow(choice)
                }
            }
        case .stamps:
            HStack(spacing: PosterSpacing.sm) {
                ForEach(Array(prompt.choices.enumerated()), id: \.element.id) { index, choice in
                    stamp(choice, symbol: stampSymbols[index % stampSymbols.count])
                }
            }
        case .note:
            noteComposer
        }
    }

    private var stampSymbols: [String] {
        ["waveform", "sun.max", "figure.walk"]
    }

    private func choiceRow(_ choice: GenerationReflectionPrompt.Choice) -> some View {
        Button {
            onSelect(choice)
        } label: {
            HStack(spacing: PosterSpacing.sm) {
                Text(choice.title)
                    .font(PosterTypography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Spacer(minLength: 0)
                if selectedChoiceID == choice.id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(
                selectedChoiceID == choice.id
                    ? PosterPalette.actionBlueDeep
                    : PosterPalette.ink
            )
            .padding(.horizontal, PosterSpacing.sm)
            .frame(
                maxWidth: .infinity,
                minHeight: HeroPhotoMetrics.minimumInteractiveHeight
            )
            .background(
                selectedChoiceID == choice.id
                    ? PosterPalette.cardActive
                    : PosterPalette.cardLight,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        selectedChoiceID == choice.id
                            ? PosterPalette.actionBlue
                            : PosterPalette.line,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityIdentifier("reality.reflection-option-\(choice.id)")
    }

    private func stamp(
        _ choice: GenerationReflectionPrompt.Choice,
        symbol: String
    ) -> some View {
        Button {
            onSelect(choice)
        } label: {
            VStack(spacing: PosterSpacing.xs) {
                Image(systemName: selectedChoiceID == choice.id ? "checkmark.seal.fill" : symbol)
                    .font(.body.weight(.semibold))
                Text(choice.title)
                    .font(PosterTypography.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(
                selectedChoiceID == choice.id
                    ? PosterPalette.actionBlueDeep
                    : PosterPalette.ink
            )
            .frame(maxWidth: .infinity, minHeight: PosterSpacing.xl * 2)
            .background(
                selectedChoiceID == choice.id
                    ? PosterPalette.cardActive
                    : PosterPalette.cardLight,
                in: RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                    .stroke(
                        selectedChoiceID == choice.id
                            ? PosterPalette.actionBlue
                            : PosterPalette.line,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityIdentifier("reality.reflection-option-\(choice.id)")
    }

    @ViewBuilder
    private var noteComposer: some View {
        if isNoteCommitted {
            sealedNote
        } else {
            VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                Text("写给这一刻")
                    .font(PosterTypography.caption.weight(.semibold))
                    .foregroundStyle(PosterPalette.mutedInk)

                TextField(prompt.notePlaceholder ?? "写一句话…", text: $note)
                    .font(PosterTypography.caption)
                    .foregroundStyle(PosterPalette.ink)
                    .lineLimit(1)
                    .padding(PosterSpacing.sm)
                    .frame(maxWidth: .infinity, minHeight: HeroPhotoMetrics.minimumInteractiveHeight)
                    .background(
                        PosterPalette.cardLight,
                        in: RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                            .stroke(PosterPalette.line, lineWidth: 1)
                    }
                    .accessibilityIdentifier("reality.reflection-note")

                Button {
                    onCommitNote()
                } label: {
                    Label("封存这句话", systemImage: "seal")
                        .font(PosterTypography.caption)
                        .foregroundStyle(PosterPalette.actionBlueDeep)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: HeroPhotoMetrics.minimumInteractiveHeight
                        )
                        .background(PosterPalette.cardActive, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(PosterPalette.actionBlue, lineWidth: 1)
                        }
                }
                .buttonStyle(PosterPressStyle())
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("reality.reflection-save-note")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Once sealed, the composer never re-shows the text field or button —
    /// their fixed-width container above already keeps their size stable
    /// while typing, but removing them entirely after commit is what makes
    /// the "sealed" state read as genuinely final rather than still-editable.
    private var sealedNote: some View {
        HStack(alignment: .top, spacing: PosterSpacing.sm) {
            Image(systemName: "seal.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(PosterPalette.actionBlueDeep)
            Text(note)
                .font(PosterTypography.caption.weight(.semibold))
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(PosterSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PosterPalette.cardActive,
            in: RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                .stroke(PosterPalette.actionBlue.opacity(0.5), lineWidth: 1)
        }
        .accessibilityIdentifier("reality.reflection-note-sealed")
    }
}

/// A quiet, three-stage trace of what happens while the pipeline keeps
/// working in the background — shown once the person has responded, so
/// sealing a note or picking an answer never leads into silent waiting.
private struct GenerationPipelineTrace: View {
    let phase: AppPhase
    let understandingProgress: Double
    let generationProgress: Double

    private let stages: [(label: String, systemImage: String)] = [
        ("理解画面", "eye"),
        ("编写故事", "text.quote"),
        ("生成画面", "sparkles"),
    ]

    private var activeIndex: Int {
        switch phase {
        case .understanding: 0
        case .storyWriting: 1
        case .generating: 2
        default: 2
        }
    }

    private var activeProgress: Double? {
        switch phase {
        case .understanding: understandingProgress
        case .generating: generationProgress
        default: nil
        }
    }

    private var nextStepCopy: String {
        switch phase {
        case .understanding:
            "接下来会先读懂这张照片，再编写故事，最后生成新的画面。"
        case .storyWriting:
            "画面已经理解完成，正在为它编写时间线索。"
        case .generating:
            "故事写好了，新的画面正在生成。"
        default:
            "完成后会自动翻回照片正面，展示这一刻的新样子。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            HStack(spacing: PosterSpacing.xs) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    stageMark(stage, index: index)
                    if index < stages.count - 1 {
                        Rectangle()
                            .fill(
                                index < activeIndex
                                    ? PosterPalette.actionBlue.opacity(0.6)
                                    : PosterPalette.line
                            )
                            .frame(height: 1)
                    }
                }
            }

            if let activeProgress {
                Capsule()
                    .fill(PosterPalette.line)
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(PosterPalette.actionBlue)
                                .frame(
                                    width: proxy.size.width
                                        * min(max(activeProgress, 0), 1)
                                )
                        }
                    }
                    .clipShape(Capsule())
            }

            Text(nextStepCopy)
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("生成进度")
        .accessibilityValue(nextStepCopy)
    }

    @ViewBuilder
    private func stageMark(
        _ stage: (label: String, systemImage: String),
        index: Int
    ) -> some View {
        let isActive = index == activeIndex
        let isDone = index < activeIndex
        VStack(spacing: 2) {
            Image(systemName: isDone ? "checkmark.circle.fill" : stage.systemImage)
                .font(.caption.weight(.bold))
            Text(stage.label)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(
            isActive || isDone
                ? PosterPalette.actionBlueDeep
                : PosterPalette.mutedInk.opacity(0.55)
        )
    }
}

/// Persistent photo host owned by ``RootView``. Survives phase swaps so the
/// capture never remounts, jumps, or fades with page opacity transitions.
struct HeroPhotoSurface: View {
    let model: AppModel
    /// RootView owns transition progression so this component remains a pure
    /// renderer of the persistent temporal photo object.
    var spatialProgress: CGFloat = 0
    /// Drives the capture card's full Y-axis flip while the print lands from
    /// the viewfinder crop into the developing paper slot.
    var captureFlipProgress: CGFloat = 0
    /// The generated photo's time-specific reveal remains distinct from the
    /// brief spatial lift that accompanies it.
    var timeRevealProgress: CGFloat = 1
    /// Enabled only on stable, post-capture stages. Viewfinder, shutter
    /// handoff, and the result time-door keep their dedicated gestures.
    var handManipulationEnabled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var generatedLayerOpacity = 0.0
    @State private var handPose = TemporalPhotoHandPose.resting
    @State private var isReflectionBack = false
    @State private var reflectionDragDegrees = 0.0
    @State private var reflectionTurnDirection = 1.0
    @State private var selectedReflectionChoiceID: String?
    @State private var reflectionNote = ""
    @State private var isReflectionNoteCommitted = false

    private var generatedImage: UIImage? {
        model.decodedGeneratedImage
    }

    private var showsSealedTarget: Bool {
        generatedImage != nil
            && (model.phase == .understanding || model.phase == .storyWriting)
    }

    private var usesPhotoPaper: Bool {
        switch model.phase {
        case .shuttered, .understanding, .storyWriting, .generating, .result:
            true
        default:
            false
        }
    }

    private var showsForegroundDepth: Bool {
        guard model.decodedForegroundMask != nil, !reduceMotion else { return false }
        switch model.phase {
        case .understanding, .storyWriting, .generating:
            return true
        default:
            return false
        }
    }

    private var foregroundDepthProgress: CGFloat {
        switch model.phase {
        case .understanding:
            return CGFloat(0.25 + model.understandingProgress * 0.75)
        case .storyWriting:
            return 1
        case .generating:
            return CGFloat(max(0.18, 1 - model.generationProgress * 0.82))
        default:
            return 0
        }
    }

    private var foregroundDepthOffset: CGSize {
        guard showsForegroundDepth else { return .zero }
        let progress = foregroundDepthProgress
        return CGSize(
            width: progress * (PosterSpacing.sm + CGFloat(model.captureMotion.roll) * PosterSpacing.md),
            height: -progress * (PosterSpacing.xs + CGFloat(model.captureMotion.pitch) * PosterSpacing.sm)
        )
    }

    /// The resting pose is deliberately flat. Only the capture handoff and the
    /// generated-result interpretation briefly drive this value toward depth.
    private var spatialRotation: (x: Double, y: Double, z: Double) {
        switch model.phase {
        case .shuttered, .understanding:
            (
                PosterMotion.captureSpatialPitchDegrees,
                PosterMotion.captureSpatialYawDegrees,
                PosterMotion.photoPaperUnderstandingRotation
            )
        case .result:
            (
                PosterMotion.resultSpatialPitchDegrees,
                PosterMotion.resultSpatialYawDegrees,
                PosterMotion.resultSpatialRollDegrees
            )
        default:
            (0, 0, 0)
        }
    }

    private var reflectionPrompt: GenerationReflectionPrompt {
        GenerationReflectionPrompt.make(for: model.generationTargetTime)
    }

    private var interactiveFlipYDegrees: Double {
        guard handManipulationEnabled, !reduceMotion else { return 0 }
        let restingDegrees = isReflectionBack ? reflectionTurnDirection * 180 : 0
        return restingDegrees + reflectionDragDegrees
    }

    var body: some View {
        Group {
            if handManipulationEnabled {
                photoContent
                    .offset(handPose.translation)
                    .contentShape(Rectangle())
                    .simultaneousGesture(handManipulationGesture)
            } else {
                photoContent.clipped()
            }
        }
        .accessibilityElement(
            children: handManipulationEnabled ? .contain : .ignore
        )
        .accessibilityIdentifier(
            handManipulationEnabled ? "hero.hand-photo" : "hero.photo"
        )
        .accessibilityLabel(
            model.phase == .result ? "生成的时间场景" : "刚刚拍下的原始照片"
        )
        .accessibilityHint(
            handManipulationEnabled
                ? "上下拖动可以拿起照片；左右转动可查看背面的时间提问"
                : ""
        )
        .accessibilityAction(
            named: isReflectionBack ? "翻回照片正面" : "翻到照片背面"
        ) {
            setReflectionBack(!isReflectionBack)
        }
        .onAppear {
            syncLayerOpacities(animated: false)
            #if DEBUG
            if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_REFLECTION_BACK"] == "1" {
                isReflectionBack = true
            }
            #endif
        }
        .onChange(of: model.decodedGeneratedImage != nil) { _, hasGenerated in
            if hasGenerated {
                crossfadeToGenerated()
            } else {
                generatedLayerOpacity = 0
            }
        }
        .onChange(of: model.generatedFrame?.id) { _, _ in
            syncLayerOpacities(animated: true)
        }
        .onChange(of: model.phase) { _, _ in
            syncLayerOpacities(animated: true)
        }
        .onChange(of: handManipulationEnabled) { _, isEnabled in
            guard !isEnabled else { return }
            handPose = .resting
            isReflectionBack = false
            reflectionDragDegrees = 0
        }
        .onChange(of: model.activeSessionID) { _, _ in
            isReflectionBack = false
            reflectionDragDegrees = 0
            selectedReflectionChoiceID = nil
            reflectionNote = ""
            isReflectionNoteCommitted = false
        }
    }

    private var photoContent: some View {
        GeometryReader { proxy in
            ZStack {
                temporalPhoto(image: model.decodedCapturedImage)

                if let generatedImage {
                    temporalPhoto(image: generatedImage)
                        .mask {
                            if model.phase == .result, !reduceMotion {
                                TimeRevealMask(progress: timeRevealProgress)
                            } else {
                                Rectangle()
                            }
                        }
                        .opacity(generatedLayerOpacity)
                        .accessibilityHidden(true)

                    if model.phase == .result {
                        TimeRevealRipple(
                            progress: timeRevealProgress,
                            reduceMotion: reduceMotion
                        )
                    }
                }

                if model.capturedPhoto == nil, model.decodedCapturedImage == nil {
                    PosterPalette.ink.opacity(0.12)
                }

                if showsSealedTarget {
                    sealedTargetOverlay
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func temporalPhoto(image: UIImage?) -> some View {
        TemporalPhotoCard(
            image: image,
            foregroundMask: showsForegroundDepth ? model.decodedForegroundMask : nil,
            foregroundOffset: foregroundDepthOffset,
            foregroundShadowOpacity: showsForegroundDepth
                ? Double(foregroundDepthProgress) * 0.24
                : 0,
            cornerRadius: usesPhotoPaper ? PosterRadius.photoPaper : 0,
            spatialProgress: spatialProgress,
            rotationXDegrees: spatialRotation.x,
            rotationYDegrees: spatialRotation.y,
            rotationZDegrees: spatialRotation.z,
            flipYDegrees: reduceMotion
                ? 0
                : FUMIRASpatialMotion.captureFlipDegrees(captureFlipProgress)
                    + interactiveFlipYDegrees,
            paperBorderEnabled: usesPhotoPaper,
            reduceMotion: reduceMotion,
            motionField: model.motionField,
            handPose: handManipulationEnabled ? handPose : .resting,
            backContent: handManipulationEnabled ? AnyView(reflectionBack) : nil,
            forceBackFace: reduceMotion && handManipulationEnabled && isReflectionBack
        )
    }

    private var handManipulationGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !reduceMotion else { return }
                let isHorizontal = abs(value.translation.width)
                    > abs(value.translation.height) * 1.1
                if isHorizontal {
                    handPose = .resting
                    reflectionDragDegrees = min(
                        max(Double(value.translation.width) * 0.58, -112),
                        112
                    )
                } else if !isReflectionBack {
                    reflectionDragDegrees = 0
                    handPose = TemporalPhotoHandPose.held(at: value.translation)
                }
            }
            .onEnded { value in
                let terminalTranslation = abs(value.predictedEndTranslation.width)
                    > abs(value.translation.width)
                    ? value.predictedEndTranslation.width
                    : value.translation.width
                let isHorizontal = abs(terminalTranslation)
                    > abs(value.translation.height) * 1.1
                if reduceMotion {
                    handPose = .resting
                    guard isHorizontal, abs(terminalTranslation) >= 52 else { return }
                    setReflectionBack(!isReflectionBack)
                    return
                }
                withAnimation(PosterMotion.photoHandSettle) {
                    handPose = .resting
                    reflectionDragDegrees = 0
                    guard isHorizontal, abs(terminalTranslation) >= 52 else { return }
                    if isReflectionBack {
                        isReflectionBack = false
                    } else {
                        reflectionTurnDirection = terminalTranslation < 0 ? -1 : 1
                        isReflectionBack = true
                    }
                }
            }
    }

    private var reflectionBack: some View {
        GenerationReflectionBack(
            prompt: reflectionPrompt,
            selectedChoiceID: selectedReflectionChoiceID,
            note: $reflectionNote,
            isNoteCommitted: isReflectionNoteCommitted,
            pipelinePhase: model.phase,
            understandingProgress: model.understandingProgress,
            generationProgress: model.generationProgress,
            onSelect: { choice in
                withAnimation(PosterMotion.interaction) {
                    selectedReflectionChoiceID = choice.id
                }
            },
            onCommitNote: {
                withAnimation(PosterMotion.interaction) {
                    isReflectionNoteCommitted = true
                }
            }
        )
    }

    private func setReflectionBack(_ isBack: Bool) {
        guard handManipulationEnabled else { return }
        if reduceMotion {
            isReflectionBack = isBack
            reflectionDragDegrees = 0
            return
        }
        withAnimation(PosterMotion.photoHandSettle) {
            if isBack, !isReflectionBack {
                reflectionTurnDirection = 1
            }
            isReflectionBack = isBack
            reflectionDragDegrees = 0
            handPose = .resting
        }
    }

    private var sealedTargetOverlay: some View {
        ZStack {
            PosterPalette.canvas

            Canvas { context, size in
                let spacing: CGFloat = 22
                var x = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(
                        path,
                        with: .color(PosterPalette.actionBlue.opacity(0.08)),
                        lineWidth: 9
                    )
                    x += spacing
                }
            }

            VStack(spacing: PosterSpacing.sm) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(PosterPalette.actionBlue)
                Text("目标画面已封存")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PosterPalette.actionBlueDeep)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.photoPaper * 0.5, style: .continuous)
                .stroke(PosterPalette.actionBlue.opacity(0.28), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("目标画面已生成，完成故事后揭晓")
    }

    private func crossfadeToGenerated() {
        guard model.phase == .result || model.phase == .share else { return }
        if reduceMotion, model.phase == .result {
            generatedLayerOpacity = 0
            withAnimation(.linear(duration: PosterMotion.reduced)) {
                generatedLayerOpacity = 1
            }
            return
        }
        // The time mask in ``TimeRevealMask`` owns result interpolation. Keep
        // this layer mounted so we do not combine it with a generic crossfade.
        generatedLayerOpacity = 1
    }

    private func syncLayerOpacities(animated: Bool) {
        let generatedTarget: Double = {
            switch model.phase {
            case .result, .share:
                return generatedImage == nil ? 0 : 1
            default:
                return 0
            }
        }()

        let apply = {
            generatedLayerOpacity = generatedTarget
        }
        if animated, reduceMotion, model.phase == .result {
            withAnimation(.linear(duration: PosterMotion.reduced)) {
                apply()
            }
        } else if animated, !reduceMotion, model.phase != .result {
            withAnimation(.easeInOut(duration: PosterMotion.heroGeneratedCrossfade)) {
                apply()
            }
        } else {
            apply()
        }
    }

}

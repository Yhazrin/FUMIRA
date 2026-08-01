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

            VStack(alignment: .leading, spacing: PosterSpacing.sm) {
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
                    Text(acknowledgement)
                        .font(PosterTypography.caption)
                        .foregroundStyle(PosterPalette.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .accessibilityIdentifier("reality.reflection-confirmation")
                }
            }
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
            VStack(spacing: PosterSpacing.xs) {
                ForEach(prompt.choices) { choice in
                    choiceRow(choice)
                }
            }
        case .stamps:
            HStack(spacing: PosterSpacing.xs) {
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

    private var noteComposer: some View {
        VStack(spacing: PosterSpacing.xs) {
            TextField(prompt.notePlaceholder ?? "写一句话…", text: $note)
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(1)
                .padding(PosterSpacing.sm)
                .frame(minHeight: HeroPhotoMetrics.minimumInteractiveHeight)
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

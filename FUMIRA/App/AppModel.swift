import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    private let dependencies: AppDependencies
    private var hasPrepared = false
    /// Single in-flight pipeline task — cancel stops URLSession poll/upload via stream termination.
    private var pipelineTask: Task<Void, Never>?
    /// Keeps repeated viewfinder entries from racing camera-session startup.
    private var cameraPreviewTask: Task<Void, Never>?
    /// Coalesces rapid pinch / Camera Control updates before publishing to ActivityKit.
    private var cameraActivityUpdateTask: Task<Void, Never>?

    var phase: AppPhase = .connection
    /// Chosen on the viewfinder, then frozen for this capture/import session.
    /// Story browsing may move `selectedTime` later, but must never silently
    /// change which year the image-generation request represents.
    var capturedTargetTime: TimePosition?
    var selectedTime: TimePosition = .now
    var understandingProgress = 0.0
    var storyProgress = 0.0
    var generationProgress = 0.0
    var generationStage: GenerationProgressStage = .preparing
    var pipelineStatusText = ""
    var hardwareSnapshot: HardwareSnapshot?
    var activeSessionID: UUID?
    var capturedPhoto: CapturedPhoto?
    /// Pre-decoded capture for the persistent hero — never decode in View bodies.
    var decodedCapturedImage: UIImage?
    /// Pre-decoded generated frame for Result / hero crossfade.
    var decodedGeneratedImage: UIImage?
    /// Bumps when the Root shutter-flash overlay should fire.
    var shutterFlashRequestID: UUID?
    var cameraAspectRatio: CameraAspectRatio = .classic
    var sceneUnderstanding: SceneUnderstanding?
    var temporalStory: TemporalStory?
    var generatedFrame: GeneratedFrame?
    /// Canonical generated result photo for Result / share surfaces.
    var generatedPhoto: CapturedPhoto?
    /// One-level in-memory undo after result regeneration (not a history library).
    var previousGeneratedFrame: GeneratedFrame?
    private var previousGeneratedPhoto: CapturedPhoto?
    private var previousSceneUnderstanding: SceneUnderstanding?
    private var previousTemporalStory: TemporalStory?
    private var previousDecodedGeneratedImage: UIImage?
    var failedStage: PipelineStage?
    var lastErrorMessage: String?
    var lastGenerationError: GenerationError?
    var posterURL: URL?
    /// Cached composed poster PNG for ShareLink / album save.
    var shareImageData: Data?
    var isPreparingPoster = false
    var isSavingPoster = false
    /// Non-error user feedback on the share screen (e.g. saved confirmation).
    var shareFeedbackMessage: String?
    var modelCatalog: AIModelCatalog = .bundled
    var modelConfiguration: AIModelConfiguration = .standard
    /// Presents the user-facing Settings sheet (advanced model routing lives inside).
    var isModelSettingsPresented = false
    var cameraControlSnapshot = CameraControlSnapshot(
        lensPosition: .back,
        flashMode: .auto,
        canSwitchCamera: false,
        supportsFlash: false
    )
    var cameraZoomSnapshot = CameraZoomSnapshot.unavailable
    var isCameraGridEnabled = false
    let motionField: MotionFieldModel
    /// A stable preview identity prevents remounting the SwiftUI/UIKit bridge
    /// whenever unrelated camera chrome state changes.
    let cameraPreview: AnyView

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        cameraPreview = dependencies.cameraPreview.makePreview()
        motionField = MotionFieldModel(service: dependencies.motionField)
    }

    var hasLiveCameraControls: Bool {
        cameraControlProvider != nil
    }

    var canSwitchCamera: Bool {
        cameraControlSnapshot.canSwitchCamera
    }

    var supportsCameraFlash: Bool {
        cameraControlSnapshot.supportsFlash
    }

    var supportsCameraZoom: Bool {
        cameraZoomSnapshot.isAvailable
    }

    private var cameraControlProvider: (any CameraControlProviding)? {
        dependencies.camera as? any CameraControlProviding
    }

    private var cameraZoomProvider: (any CameraZoomProviding)? {
        dependencies.camera as? any CameraZoomProviding
    }

    var isPipelineBusy: Bool {
        switch phase {
        case .shuttered, .understanding, .storyWriting, .generating:
            true
        default:
            false
        }
    }

    var canRetryFailedStage: Bool {
        lastGenerationError?.isRetryable ?? true
    }

    var isUsingLiveCamera: Bool {
        dependencies.cameraPreview.isLive
    }

    var canUndoGeneration: Bool {
        previousGeneratedFrame != nil
    }

    var currentNarrative: String {
        temporalStory?.narrative(for: selectedTime)
            ?? "FUMIRA 会先读懂源场景，再写出连续时间故事，并生成那一刻的照片。"
    }

    var currentStoryBeat: StoryBeat? {
        temporalStory?.beat(for: selectedTime)
    }

    var generationTargetTime: TimePosition {
        capturedTargetTime ?? generatedFrame?.time ?? selectedTime
    }

    func modelOption(for role: AIModelRole) -> AIModelOption? {
        modelCatalog.option(id: modelConfiguration.optionID(for: role))
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        await dependencies.cameraActivity.dismissAll()
        do {
            modelCatalog = try await dependencies.modelCatalog.catalog()
            let stored = await dependencies.modelConfigurationStore.load()
            modelConfiguration = sanitized(stored)
        } catch {
            modelCatalog = .bundled
            modelConfiguration = .standard
            lastErrorMessage = "模型目录暂时不可用，已切换到 FUMIRA 标准路由。"
        }
    }

    func beginHardwarePath() {
        phase = .bluetoothPermission
    }

    func beginPhoneOnlyPath() {
        phase = .cameraPermission
    }

    func grantBluetoothAndConnect() async {
        do {
            hardwareSnapshot = try await dependencies.hardware.connect()
            phase = .connected
            dependencies.haptics.play(.success)
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .disconnected
        }
    }

    func continueFromConnection() {
        phase = .cameraPermission
    }

    func grantCameraAccess() async {
        do {
            _ = try await dependencies.camera.requestAuthorization()
            phase = .viewfinder
            scheduleCameraPreview()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func openSettings() {
        isModelSettingsPresented = true
    }

    func refreshCameraControls() async {
        guard let provider = cameraControlProvider else {
            cameraControlSnapshot = CameraControlSnapshot(
                lensPosition: .back,
                flashMode: .auto,
                canSwitchCamera: false,
                supportsFlash: false
            )
            return
        }
        cameraControlSnapshot = await provider.currentControls()
    }

    func refreshCameraZoom() async {
        guard let provider = cameraZoomProvider else {
            cameraZoomSnapshot = .unavailable
            return
        }
        provider.setZoomObserver { [weak self] snapshot in
            self?.cameraZoomSnapshot = snapshot
            self?.scheduleCameraActivityUpdate()
        }
        cameraZoomSnapshot = await provider.currentZoom()
    }

    func setCameraZoomFactor(_ factor: CGFloat) {
        guard let provider = cameraZoomProvider, cameraZoomSnapshot.isAvailable else {
            return
        }
        cameraZoomSnapshot = cameraZoomSnapshot.clamping(factor)
        provider.setZoomFactor(cameraZoomSnapshot.factor)
        scheduleCameraActivityUpdate()
    }

    func resetCameraZoom() {
        setCameraZoomFactor(1)
        dependencies.haptics.play(.selection)
    }

    func switchCameraLens() async {
        guard let provider = cameraControlProvider else { return }
        do {
            cameraControlSnapshot = try await provider.switchCamera()
            await refreshCameraZoom()
            dependencies.haptics.play(.selection)
            scheduleCameraActivityUpdate()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func cycleFlashMode() async {
        guard let provider = cameraControlProvider else { return }
        guard cameraControlSnapshot.supportsFlash else { return }
        do {
            cameraControlSnapshot = try await provider.setFlashMode(
                cameraControlSnapshot.flashMode.next
            )
            dependencies.haptics.play(.selection)
            scheduleCameraActivityUpdate()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func toggleCameraGrid() {
        isCameraGridEnabled.toggle()
        dependencies.haptics.play(.selection)
        scheduleCameraActivityUpdate()
    }

    func selectCameraAspectRatio(_ aspectRatio: CameraAspectRatio) {
        guard cameraAspectRatio != aspectRatio else { return }
        cameraAspectRatio = aspectRatio
        dependencies.haptics.play(.selection)
        scheduleCameraActivityUpdate()
    }

    func triggerCameraLiveActivity() async {
        do {
            try await dependencies.cameraActivity.trigger(
                with: cameraActivityState(phase: .framing)
            )
            lastErrorMessage = nil
            dependencies.haptics.play(.selection)
        } catch {
            lastErrorMessage = error.localizedDescription
            dependencies.haptics.play(.selection)
        }
    }

    func playShutterPressHaptic() {
        dependencies.haptics.play(.shutterPress)
    }

    /// Independent Root overlay flash — does not fade page content.
    func requestShutterFlash() {
        shutterFlashRequestID = UUID()
    }

    /// Album import — same pipeline as shutter capture (understand → story → generate).
    func importPhoto(imageData: Data) async {
        guard validateRunnableConfiguration() else { return }
        guard !isPipelineBusy else { return }
        invalidatePipelineWork()
        let sessionID = UUID()
        activeSessionID = sessionID
        clearPipelineResult()
        capturedTargetTime = selectedTime
        let composition = cameraAspectRatio
        dependencies.haptics.play(.shutter)

        let task = Task { [sessionID, composition] in
            do {
                let photo = try PhotoImportAdapter.makeCapturedPhoto(
                    from: imageData,
                    composition: composition
                )
                guard !Task.isCancelled, activeSessionID == sessionID else { return }

                let decoded = await Self.decodeForDisplay(photo.data)
                guard !Task.isCancelled, activeSessionID == sessionID else { return }

                capturedPhoto = photo
                decodedCapturedImage = decoded
                await dependencies.camera.stopPreview()
                phase = .shuttered
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                await startSourcePipeline(
                    photo: photo,
                    targetTime: capturedTargetTime ?? selectedTime,
                    sessionID: sessionID
                )
            } catch is CancellationError {
                return
            } catch {
                presentFailure(stage: .capture, error: error, sessionID: sessionID)
                await resumeCameraPreview()
            }
        }
        pipelineTask = task
        await task.value
    }

    func capture() async {
        guard validateRunnableConfiguration() else { return }
        guard !isPipelineBusy else { return }
        invalidatePipelineWork()
        let sessionID = UUID()
        activeSessionID = sessionID
        clearPipelineResult()
        capturedTargetTime = selectedTime
        let composition = cameraAspectRatio
        dependencies.haptics.play(.shutter)
        requestShutterFlash()
        await dependencies.cameraActivity.update(
            with: cameraActivityState(phase: .capturing)
        )

        let task = Task { [sessionID, composition] in
            do {
                let photo = try await dependencies.camera.capturePhoto(composition: composition)
                guard !Task.isCancelled, activeSessionID == sessionID else { return }

                // Decode off the main render path before committing UI state.
                let decoded = await Self.decodeForDisplay(photo.data)
                guard !Task.isCancelled, activeSessionID == sessionID else { return }

                capturedPhoto = photo
                decodedCapturedImage = decoded
                await dependencies.cameraActivity.finish(
                    with: cameraActivityState(phase: .captured)
                )
                // Freeze in place on the shutter stage while the hero crossfades.
                phase = .shuttered
                try? await Task.sleep(
                    for: .milliseconds(Int(PosterMotion.heroCaptureCrossfade * 1_000))
                )
                guard !Task.isCancelled, activeSessionID == sessionID else { return }

                // Stop preview only after the still is on screen.
                await dependencies.camera.stopPreview()

                // A short dwell lets the live preview hand off to the still.
                // Then: understand source → write story → generate target image.
                try? await Task.sleep(
                    for: .milliseconds(Int(PosterMotion.shutterDwell * 1_000))
                )
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                await startSourcePipeline(
                    photo: photo,
                    targetTime: capturedTargetTime ?? selectedTime,
                    sessionID: sessionID
                )
            } catch is CancellationError {
                return
            } catch {
                await dependencies.cameraActivity.dismissAll()
                presentFailure(stage: .capture, error: error, sessionID: sessionID)
                await resumeCameraPreview()
            }
        }
        pipelineTask = task
        await task.value
    }

    /// Source photo → Scene Bible → story → story-driven image generation.
    private func startSourcePipeline(
        photo: CapturedPhoto,
        targetTime: TimePosition,
        sessionID: UUID
    ) async {
        await startUnderstanding(
            photo: photo,
            targetTime: targetTime,
            sessionID: sessionID
        )
    }

    private func startImageGeneration(
        photo: CapturedPhoto,
        targetTime: TimePosition,
        sessionID: UUID,
        understanding: SceneUnderstanding? = nil,
        story: TemporalStory? = nil
    ) async {
        guard let option = modelOption(for: .image) else {
            presentConfigurationFailure()
            return
        }

        generationProgress = 0
        generationStage = .preparing
        pipelineStatusText = "正在把照片送往\(targetTime.compactLabel)"
        failedStage = nil
        lastGenerationError = nil
        lastErrorMessage = nil
        phase = .generating

        let resolvedUnderstanding = understanding ?? sceneUnderstanding
        let resolvedStory = story ?? temporalStory
        let resolvedBeat = resolvedStory?.beat(for: targetTime)
        // Mock mode still gets a short local fallback string for GeneratedFrame.
        // Remote generation ignores client prompt authorship.
        let prompt = TemporalImagePrompt.make(for: targetTime)

        do {
            let events = await dependencies.generation.generate(
                request: ImageGenerationRequest(
                    photo: photo,
                    time: targetTime,
                    prompt: prompt,
                    sessionID: sessionID,
                    model: option,
                    understanding: resolvedUnderstanding,
                    temporalStory: resolvedStory,
                    storyBeat: resolvedBeat
                )
            )
            for try await event in events {
                try Task.checkCancellation()
                guard activeSessionID == sessionID else { return }
                switch event {
                case let .progress(label, value, stage):
                    pipelineStatusText = label
                    generationProgress = value
                    generationStage = stage
                case let .completed(frame):
                    guard let imageData = frame.imageData, !imageData.isEmpty else {
                        throw GenerationError.generationFailed(message: "目标照片已经生成，但图片内容为空。")
                    }
                    let decoded = await Self.decodeForDisplay(imageData)
                    guard
                        !Task.isCancelled,
                        activeSessionID == sessionID,
                        let decoded
                    else {
                        if Task.isCancelled { return }
                        throw GenerationError.generationFailed(message: "目标照片无法读取，请重试。")
                    }

                    let targetPhoto = Self.makeGeneratedPhoto(
                        imageData: imageData,
                        decodedImage: decoded
                    )
                    let completedFrame: GeneratedFrame
                    if let beatID = resolvedBeat?.id, frame.storyBeatID == nil {
                        completedFrame = GeneratedFrame(
                            id: frame.id,
                            sessionID: frame.sessionID,
                            time: frame.time,
                            storyBeatID: beatID,
                            prompt: frame.prompt,
                            modelOptionID: frame.modelOptionID,
                            imageData: frame.imageData
                        )
                    } else {
                        completedFrame = frame
                    }
                    generatedFrame = completedFrame
                    generatedPhoto = targetPhoto
                    decodedGeneratedImage = decoded
                    generationProgress = 1
                    generationStage = .finishing
                    pipelineStatusText = "照片与故事已经准备好"
                    phase = .result
                    dependencies.haptics.play(.reveal)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            presentFailure(stage: .imageGeneration, error: error, sessionID: sessionID)
        }
    }

    func startUnderstanding(
        photo: CapturedPhoto,
        targetTime: TimePosition,
        sessionID: UUID
    ) async {
        guard let option = modelOption(for: .understanding) else {
            presentConfigurationFailure()
            return
        }
        understandingProgress = 0
        pipelineStatusText = "正在读取源场景的空间锚点与时间层"
        phase = .understanding

        do {
            let events = await dependencies.understanding.analyze(
                request: ImageUnderstandingRequest(
                    photo: photo,
                    targetTime: targetTime,
                    sessionID: sessionID,
                    model: option
                )
            )
            for try await event in events {
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                switch event {
                case let .progress(label, value):
                    pipelineStatusText = label
                    understandingProgress = value
                case let .completed(value):
                    understandingProgress = 1
                    sceneUnderstanding = value
                    await startStoryWriting(
                        understanding: value,
                        targetTime: targetTime,
                        sessionID: sessionID,
                        sourcePhoto: photo
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            presentFailure(stage: .understanding, error: error, sessionID: sessionID)
        }
    }

    func startStoryWriting(
        understanding: SceneUnderstanding,
        targetTime: TimePosition,
        sessionID: UUID,
        sourcePhoto: CapturedPhoto? = nil
    ) async {
        guard let option = modelOption(for: .story) else {
            presentConfigurationFailure()
            return
        }
        storyProgress = 0
        pipelineStatusText = "正在根据源场景编写连续时间故事"
        phase = .storyWriting

        do {
            let events = await dependencies.story.write(
                request: StoryRequest(
                    understanding: understanding,
                    targetTime: targetTime,
                    sessionID: sessionID,
                    model: option
                )
            )
            for try await event in events {
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                switch event {
                case let .progress(label, value):
                    pipelineStatusText = label
                    storyProgress = value
                case let .completed(value):
                    storyProgress = 1
                    temporalStory = value
                    let photo = sourcePhoto ?? capturedPhoto
                    guard let photo else {
                        pipelineStatusText = "照片与故事已经准备好"
                        phase = .result
                        dependencies.haptics.play(.reveal)
                        return
                    }
                    await startImageGeneration(
                        photo: photo,
                        targetTime: targetTime,
                        sessionID: sessionID,
                        understanding: understanding,
                        story: value
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            presentFailure(stage: .story, error: error, sessionID: sessionID)
        }
    }

    /// Starts a fresh story-driven generation from the original capture.
    /// Used for result regeneration and explicit generation at a browsed year.
    func generateStoryWorld() async {
        guard !isPipelineBusy, let photo = capturedPhoto else { return }

        if generatedFrame != nil {
            preserveCurrentResultForUndo()
        }
        invalidatePipelineWork()
        let sessionID = UUID()
        activeSessionID = sessionID
        let targetTime = generationTargetTime
        let existingUnderstanding = sceneUnderstanding
        let existingStory = temporalStory
        prepareForNewTargetResult()

        let task = Task { [photo, sessionID, targetTime, existingUnderstanding, existingStory] in
            if let existingUnderstanding, let existingStory {
                await startImageGeneration(
                    photo: photo,
                    targetTime: targetTime,
                    sessionID: sessionID,
                    understanding: existingUnderstanding,
                    story: existingStory
                )
            } else {
                await startSourcePipeline(
                    photo: photo,
                    targetTime: targetTime,
                    sessionID: sessionID
                )
            }
        }
        pipelineTask = task
        await task.value
    }

    func regenerateStory() async {
        guard let understanding = sceneUnderstanding else {
            retake()
            return
        }
        guard !isPipelineBusy else { return }
        invalidatePipelineWork()
        let sessionID = UUID()
        activeSessionID = sessionID
        temporalStory = nil
        let task = Task {
            await startStoryWriting(
                understanding: understanding,
                targetTime: generationTargetTime,
                sessionID: sessionID,
                sourcePhoto: capturedPhoto
            )
        }
        pipelineTask = task
        await task.value
    }

        /// Re-run image generation with the same source photo + current time position.
    /// Replaces the current result; keeps one previous frame in memory for undo.
    func regenerateResult() async {
        guard capturedPhoto != nil else {
            retake()
            return
        }
        await generateStoryWorld()
    }

    /// Deliberate exploration strategy: promote the story browser's current
    /// year to a new generation target. The default generation action never
    /// does this implicitly.
    func generateAtStoryPreviewTime() async {
        capturedTargetTime = selectedTime
        await generateStoryWorld()
    }

    func undoLastGeneration() {
        guard let previous = previousGeneratedFrame else { return }
        generatedFrame = previous
        generatedPhoto = previousGeneratedPhoto
        sceneUnderstanding = previousSceneUnderstanding
        temporalStory = previousTemporalStory
        decodedGeneratedImage = previousDecodedGeneratedImage
        previousGeneratedFrame = nil
        previousGeneratedPhoto = nil
        previousSceneUnderstanding = nil
        previousTemporalStory = nil
        previousDecodedGeneratedImage = nil
        capturedTargetTime = previous.time
        selectedTime = previous.time
        phase = .result
        dependencies.haptics.play(.selection)
        if decodedGeneratedImage == nil {
            Task {
                decodedGeneratedImage = await Self.decodeForDisplay(previous.imageData)
            }
        }
    }

    func retryPipeline() async {
        guard !isPipelineBusy else { return }
        guard let stage = failedStage else {
            retake()
            return
        }
        guard canRetryFailedStage || stage == .configuration else {
            // Non-retryable: return to the previous result or camera instead of
            // immediately submitting the same invalid request again.
            showOriginalNow()
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        failedStage = nil
        lastErrorMessage = nil
        lastGenerationError = nil

        switch stage {
        case .configuration:
            isModelSettingsPresented = true
            phase = restorePreviousResultIfAvailable() ? .result : .viewfinder
        case .capture:
            phase = .viewfinder
            await resumeCameraPreview()
        case .understanding:
            if let photo = generatedPhoto {
                let task = Task {
                    await startUnderstanding(
                        photo: photo,
                        targetTime: generationTargetTime,
                        sessionID: sessionID
                    )
                }
                pipelineTask = task
                await task.value
            } else {
                retake()
            }
        case .story:
            if let understanding = sceneUnderstanding {
                let task = Task {
                    await startStoryWriting(
                        understanding: understanding,
                        targetTime: generationTargetTime,
                        sessionID: sessionID
                    )
                }
                pipelineTask = task
                await task.value
            } else if let photo = generatedPhoto {
                let task = Task {
                    await startUnderstanding(
                        photo: photo,
                        targetTime: generationTargetTime,
                        sessionID: sessionID
                    )
                }
                pipelineTask = task
                await task.value
            }
        case .imageGeneration:
            await generateStoryWorld()
        }
    }

    /// Cancel in-flight generation (and stop remote poll/upload). A result
    /// regeneration returns to the previous reveal; first generation returns
    /// to the camera without exposing an unfinished target frame.
    func cancelGeneration() {
        guard phase == .generating else { return }
        invalidatePipelineWork()
        generationProgress = 0
        generationStage = .preparing
        pipelineStatusText = ""
        failedStage = nil
        lastGenerationError = nil
        lastErrorMessage = nil
        if restorePreviousResultIfAvailable() {
            phase = .result
        } else {
            phase = .viewfinder
            Task { await resumeCameraPreview() }
        }
        dependencies.haptics.play(.selection)
    }

    /// Cancel any busy pipeline stage and land on a safe phase.
    func cancelPipeline() {
        switch phase {
        case .generating:
            cancelGeneration()
        case .shuttered, .understanding, .storyWriting:
            invalidatePipelineWork()
            understandingProgress = 0
            storyProgress = 0
            pipelineStatusText = ""
            failedStage = nil
            lastGenerationError = nil
            lastErrorMessage = nil
            if restorePreviousResultIfAvailable() {
                phase = .result
            } else {
                phase = .viewfinder
                Task { await resumeCameraPreview() }
            }
            dependencies.haptics.play(.selection)
        default:
            break
        }
    }

    func showOriginalNow() {
        invalidatePipelineWork()
        failedStage = nil
        lastGenerationError = nil
        if restorePreviousResultIfAvailable() {
            phase = .result
        } else if generatedFrame != nil {
            // A completed target image can still be revealed after a later
            // story rewrite / regeneration failure without discarding it.
            phase = .result
        } else {
            selectedTime = .now
            phase = .viewfinder
            Task { await resumeCameraPreview() }
        }
    }

    func updateTime(normalized: Double) {
        selectedTime = TimePosition(normalized: normalized)
        scheduleCameraActivityUpdate()
    }

    func playTimeDetent(_ detent: WaveTimeDetent) {
        dependencies.haptics.play(detent == .now ? .timeAnchor : .timeDetent)
    }

    func syncMotionField(
        for phase: AppPhase,
        reduceMotion: Bool,
        lowPowerMode: Bool
    ) {
        let thermalState = ProcessInfo.processInfo.thermalState
        let thermallyConstrained = thermalState == .serious || thermalState == .critical
        guard Self.isMotionEligible(phase), !thermallyConstrained else {
            motionField.deactivate()
            return
        }
        motionField.activate(reduceMotion: reduceMotion, lowPowerMode: lowPowerMode)
    }

    private static func isMotionEligible(_ phase: AppPhase) -> Bool {
        switch phase {
        case .connection, .result, .share:
            true
        default:
            false
        }
    }

    func openShare() {
        dependencies.haptics.play(.save)
        shareFeedbackMessage = nil
        lastErrorMessage = nil
        phase = .share
        Task { await prepareSharePoster() }
    }

    func returnToResult() {
        phase = .result
        shareFeedbackMessage = nil
    }

    /// Minimal `fumira://` deep link used by sharing and the Live Activity controls.
    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "fumira" else { return }
        let host = (url.host ?? url.pathComponents.dropFirst().first)?.lowercased()
        switch host {
        case "camera":
            handleCameraActivityDeepLink(url)
        case "share":
            guard temporalStory != nil || generatedFrame != nil else { return }
            openShare()
        case "result":
            guard generatedFrame != nil || temporalStory != nil else { return }
            phase = .result
        default:
            break
        }
    }

    var shareablePoster: ShareablePosterPNG? {
        guard let shareImageData, !shareImageData.isEmpty else { return nil }
        return ShareablePosterPNG(data: shareImageData)
    }

    func prepareSharePoster() async {
        guard !isPreparingPoster else { return }
        isPreparingPoster = true
        defer { isPreparingPoster = false }
        do {
            shareImageData = try composePosterPNG()
            if lastErrorMessage?.contains("海报") == true {
                lastErrorMessage = nil
            }
        } catch {
            shareImageData = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func savePosterToLibrary() async {
        guard !isSavingPoster else { return }
        isSavingPoster = true
        defer { isSavingPoster = false }
        shareFeedbackMessage = nil
        do {
            let data = try shareImageData ?? composePosterPNG()
            shareImageData = data
            let snapshot = PosterSnapshot(
                time: selectedTime,
                title: temporalStory?.title ?? currentStoryBeat?.title ?? "这一刻的时间故事",
                yearLabel: PosterComposer.yearLabel(for: selectedTime),
                imageData: data
            )
            posterURL = try await dependencies.storage.save(snapshot)
            dependencies.haptics.play(.success)
            shareFeedbackMessage = "已保存到相册"
            lastErrorMessage = nil
        } catch {
            shareFeedbackMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func playShareHaptic() {
        dependencies.haptics.play(.save)
    }

    private func composePosterPNG() throws -> Data {
        try PosterComposer.renderPNG(
            time: selectedTime,
            yearLabel: PosterComposer.yearLabel(for: selectedTime),
            title: temporalStory?.title ?? currentStoryBeat?.title ?? "这一刻的时间故事",
            narrative: currentNarrative,
            sceneImageData: generatedFrame?.imageData
        )
    }

    func retake() {
        invalidatePipelineWork()
        clearPipelineResult()
        phase = .viewfinder
        scheduleCameraPreview()
    }

    func recoverConnection() {
        phase = .connection
    }

    func presentFailureForPreview() {
        invalidatePipelineWork()
        failedStage = .imageGeneration
        lastGenerationError = .timedOut
        lastErrorMessage = GenerationError.timedOut.errorDescription
        phase = .pipelineFailure
    }

    func selectModel(optionID: String, for role: AIModelRole) async {
        guard
            let option = modelCatalog.option(id: optionID),
            option.role == role,
            option.availability == .ready
        else {
            lastErrorMessage = "这个模型路由还需要后台接入后才能启用。"
            return
        }
        modelConfiguration.select(optionID: optionID, for: role)
        do {
            try await dependencies.modelConfigurationStore.save(modelConfiguration)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "模型选择已在本次运行生效，但暂时无法保存。"
        }
    }

    private func sanitized(
        _ configuration: AIModelConfiguration
    ) -> AIModelConfiguration {
        var result = configuration
        for role in AIModelRole.allCases {
            guard
                let option = modelCatalog.option(id: configuration.optionID(for: role)),
                option.role == role,
                option.availability == .ready
            else {
                result.select(optionID: AIModelConfiguration.standard.optionID(for: role), for: role)
                continue
            }
        }
        return result
    }

    private func validateRunnableConfiguration() -> Bool {
        guard modelCatalog.isRunnable(modelConfiguration) else {
            presentConfigurationFailure()
            return false
        }
        return true
    }

    private func presentConfigurationFailure() {
        invalidatePipelineWork()
        failedStage = .configuration
        lastGenerationError = nil
        lastErrorMessage = "当前模型组合尚未全部接通，请在设置 → 高级中选择可运行路由。"
        phase = .pipelineFailure
    }

    private func presentFailure(
        stage: PipelineStage,
        error: Error,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID else { return }
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }

        activeSessionID = nil
        pipelineTask = nil
        failedStage = stage
        let classified = Self.classify(error)
        lastGenerationError = classified
        lastErrorMessage = classified.errorDescription ?? error.localizedDescription
        phase = .pipelineFailure
    }

    private static func classify(_ error: Error) -> GenerationError {
        if let generationError = error as? GenerationError {
            return generationError
        }
        return .generationFailed(message: error.localizedDescription)
    }

    /// Invalidate the active session and cancel the in-flight pipeline Task (stops remote poll).
    private func invalidatePipelineWork() {
        activeSessionID = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        cameraActivityUpdateTask?.cancel()
        cameraActivityUpdateTask = nil
    }

    private func resumeCameraPreview() async {
        do {
            try await dependencies.camera.startPreview()
            guard !Task.isCancelled, phase == .viewfinder else { return }
            await refreshCameraControls()
            await refreshCameraZoom()
        } catch is CancellationError {
            return
        } catch {
            guard phase == .viewfinder else { return }
            lastErrorMessage = error.localizedDescription
            lastGenerationError = Self.classify(error)
            failedStage = .capture
            phase = .pipelineFailure
        }
    }

    private func scheduleCameraPreview() {
        cameraPreviewTask?.cancel()
        cameraPreviewTask = Task { [weak self] in
            await self?.resumeCameraPreview()
        }
    }

    private func scheduleCameraActivityUpdate() {
        guard phase == .viewfinder else { return }
        cameraActivityUpdateTask?.cancel()
        cameraActivityUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, self.phase == .viewfinder else { return }
            await self.dependencies.cameraActivity.update(
                with: self.cameraActivityState(phase: .framing)
            )
        }
    }

    private func cameraActivityState(
        phase: CameraLiveActivityAttributes.ContentState.Phase
    ) -> CameraLiveActivityAttributes.ContentState {
        let zoomFactor = cameraZoomSnapshot.displayFactor
        let zoomLabel = zoomFactor < 10
            ? String(format: "%.1f×", Double(zoomFactor))
            : String(format: "%.0f×", Double(zoomFactor))

        return CameraLiveActivityAttributes.ContentState(
            phase: phase,
            targetLabel: selectedTime.compactLabel,
            zoomLabel: zoomLabel,
            flashSymbol: cameraControlSnapshot.flashMode.systemImageName,
            lensSymbol: cameraControlSnapshot.lensPosition == .front
                ? "camera.rotate.fill"
                : "arrow.triangle.2.circlepath",
            isGridEnabled: isCameraGridEnabled,
            aspectRatioLabel: cameraAspectRatio.label
        )
    }

    private func handleCameraActivityDeepLink(_ url: URL) {
        guard phase == .viewfinder else { return }
        let action = url.pathComponents.dropFirst().first?.lowercased()

        switch action {
        case "flash":
            Task { await cycleFlashMode() }
        case "lens":
            Task { await switchCameraLens() }
        case "grid":
            toggleCameraGrid()
        case "aspect":
            selectCameraAspectRatio(nextCameraAspectRatio)
        default:
            scheduleCameraPreview()
        }
    }

    private var nextCameraAspectRatio: CameraAspectRatio {
        switch cameraAspectRatio {
        case .fullScreen: .widescreen
        case .widescreen: .classic
        case .classic: .square
        case .square: .fullScreen
        }
    }

    private func preserveCurrentResultForUndo() {
        previousGeneratedFrame = generatedFrame
        previousGeneratedPhoto = generatedPhoto
        previousSceneUnderstanding = sceneUnderstanding
        previousTemporalStory = temporalStory
        previousDecodedGeneratedImage = decodedGeneratedImage
    }

    private func prepareForNewTargetResult() {
        generatedFrame = nil
        generatedPhoto = nil
        decodedGeneratedImage = nil
        // Keep Scene Bible + story across regenerations so every target year
        // reuses the same source understanding (no chain drift).
        understandingProgress = 0
        storyProgress = 0
        generationProgress = 0
        generationStage = .preparing
        pipelineStatusText = ""
        failedStage = nil
        lastErrorMessage = nil
        lastGenerationError = nil
        shareImageData = nil
        posterURL = nil
    }

    @discardableResult
    private func restorePreviousResultIfAvailable() -> Bool {
        guard let previous = previousGeneratedFrame else { return false }
        generatedFrame = previous
        generatedPhoto = previousGeneratedPhoto
        sceneUnderstanding = previousSceneUnderstanding
        temporalStory = previousTemporalStory
        decodedGeneratedImage = previousDecodedGeneratedImage
        capturedTargetTime = previous.time
        selectedTime = previous.time
        previousGeneratedFrame = nil
        previousGeneratedPhoto = nil
        previousSceneUnderstanding = nil
        previousTemporalStory = nil
        previousDecodedGeneratedImage = nil
        return true
    }

    private func clearPipelineResult() {
        capturedTargetTime = nil
        capturedPhoto = nil
        decodedCapturedImage = nil
        decodedGeneratedImage = nil
        sceneUnderstanding = nil
        temporalStory = nil
        generatedFrame = nil
        generatedPhoto = nil
        previousGeneratedFrame = nil
        previousGeneratedPhoto = nil
        previousSceneUnderstanding = nil
        previousTemporalStory = nil
        previousDecodedGeneratedImage = nil
        understandingProgress = 0
        storyProgress = 0
        generationProgress = 0
        generationStage = .preparing
        pipelineStatusText = ""
        failedStage = nil
        lastErrorMessage = nil
        lastGenerationError = nil
        posterURL = nil
        shareImageData = nil
        shareFeedbackMessage = nil
        isPreparingPoster = false
        isSavingPoster = false
    }

    private static func makeGeneratedPhoto(
        imageData: Data,
        decodedImage: UIImage
    ) -> CapturedPhoto {
        let scale = max(decodedImage.scale, 1)
        return CapturedPhoto(
            data: imageData,
            pixelWidth: max(Int((decodedImage.size.width * scale).rounded()), 1),
            pixelHeight: max(Int((decodedImage.size.height * scale).rounded()), 1)
        )
    }

    /// Decode + prepare on a background cooperative task; return nil when data is empty.
    private static func decodeForDisplay(_ data: Data?) async -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
    }

    private static func decodeForDisplay(_ data: Data) async -> UIImage? {
        await decodeForDisplay(Optional(data))
    }
}

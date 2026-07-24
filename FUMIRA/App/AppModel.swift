import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private let dependencies: AppDependencies
    private var hasPrepared = false
    /// Single in-flight pipeline task — cancel stops URLSession poll/upload via stream termination.
    private var pipelineTask: Task<Void, Never>?

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
    var cameraAspectRatio: CameraAspectRatio = .classic
    var sceneUnderstanding: SceneUnderstanding?
    var temporalStory: TemporalStory?
    var generatedFrame: GeneratedFrame?
    /// One-level in-memory undo after result regeneration (not a history library).
    var previousGeneratedFrame: GeneratedFrame?
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
    var isCameraGridEnabled = false
    let motionField: MotionFieldModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
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

    private var cameraControlProvider: (any CameraControlProviding)? {
        dependencies.camera as? any CameraControlProviding
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

    var cameraPreview: AnyView {
        dependencies.cameraPreview.makePreview()
    }

    var currentNarrative: String {
        temporalStory?.narrative(for: selectedTime)
            ?? "先拍下一张照片，FUMIRA 会读懂画面，再为同一个地方写出跨越时间的故事。"
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
            await refreshCameraControls()
            phase = .viewfinder
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

    func switchCameraLens() async {
        guard let provider = cameraControlProvider else { return }
        do {
            cameraControlSnapshot = try await provider.switchCamera()
            dependencies.haptics.play(.selection)
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
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func toggleCameraGrid() {
        isCameraGridEnabled.toggle()
        dependencies.haptics.play(.selection)
    }

    func selectCameraAspectRatio(_ aspectRatio: CameraAspectRatio) {
        guard cameraAspectRatio != aspectRatio else { return }
        cameraAspectRatio = aspectRatio
        dependencies.haptics.play(.selection)
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

        let task = Task { [sessionID, composition] in
            do {
                let photo = try await dependencies.camera.capturePhoto(composition: composition)
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                capturedPhoto = photo
                await dependencies.camera.stopPreview()
                phase = .shuttered
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                await startUnderstanding(photo: photo, sessionID: sessionID)
            } catch is CancellationError {
                return
            } catch {
                presentFailure(stage: .capture, error: error, sessionID: sessionID)
            }
        }
        pipelineTask = task
        await task.value
    }

    /// Album import — same pipeline as shutter capture (understanding → story → generate).
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
                capturedPhoto = photo
                await dependencies.camera.stopPreview()
                phase = .shuttered
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                await startUnderstanding(photo: photo, sessionID: sessionID)
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

    func startUnderstanding(photo: CapturedPhoto, sessionID: UUID) async {
        guard let option = modelOption(for: .understanding) else {
            presentConfigurationFailure()
            return
        }
        understandingProgress = 0
        pipelineStatusText = "准备理解画面"
        phase = .understanding

        do {
            let events = await dependencies.understanding.analyze(
                request: ImageUnderstandingRequest(
                    photo: photo,
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
                    await startStoryWriting(understanding: value, sessionID: sessionID)
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
        sessionID: UUID
    ) async {
        guard let option = modelOption(for: .story) else {
            presentConfigurationFailure()
            return
        }
        storyProgress = 0
        pipelineStatusText = "准备时间线"
        phase = .storyWriting

        do {
            let events = await dependencies.story.write(
                request: StoryRequest(
                    understanding: understanding,
                    targetTime: generationTargetTime,
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
                    phase = .storyReady
                    dependencies.haptics.play(.success)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            presentFailure(stage: .story, error: error, sessionID: sessionID)
        }
    }

    func generateStoryWorld() async {
        // Debounce: ignore duplicate taps while already generating.
        guard phase == .storyReady || phase == .pipelineFailure || phase == .result else { return }
        guard
            let photo = capturedPhoto,
            let understanding = sceneUnderstanding,
            let story = temporalStory,
            let option = modelOption(for: .image)
        else {
            presentConfigurationFailure()
            return
        }

        invalidatePipelineWork()
        let sessionID = UUID()
        activeSessionID = sessionID
        generationProgress = 0
        generationStage = .preparing
        pipelineStatusText = "准备让时间生长"
        failedStage = nil
        lastGenerationError = nil
        lastErrorMessage = nil
        phase = .generating
        let targetTime = generationTargetTime

        let task = Task { [photo, understanding, story, option, sessionID, targetTime] in
            do {
                let events = await dependencies.generation.generate(
                    request: ImageGenerationRequest(
                        photo: photo,
                        understanding: understanding,
                        story: story,
                        time: targetTime,
                        sessionID: sessionID,
                        model: option
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
                        generatedFrame = frame
                        generationProgress = 1
                        generationStage = .finishing
                        pipelineStatusText = "这一帧已经长成"
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
            await startStoryWriting(understanding: understanding, sessionID: sessionID)
        }
        pipelineTask = task
        await task.value
    }

    /// Re-run image generation with the same source photo + current time position.
    /// Replaces the current result; keeps one previous frame in memory for undo.
    func regenerateResult() async {
        guard
            capturedPhoto != nil,
            sceneUnderstanding != nil,
            temporalStory != nil
        else {
            retake()
            return
        }
        previousGeneratedFrame = generatedFrame
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
        previousGeneratedFrame = nil
        phase = .result
        dependencies.haptics.play(.selection)
    }

    func retryPipeline() async {
        guard !isPipelineBusy else { return }
        guard let stage = failedStage else {
            retake()
            return
        }
        guard canRetryFailedStage || stage == .configuration else {
            // Non-retryable: send the user back to adjust story / time instead of re-hitting the API.
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
            phase = capturedPhoto == nil ? .viewfinder : .storyReady
        case .capture:
            phase = .viewfinder
            await resumeCameraPreview()
        case .understanding:
            if let photo = capturedPhoto {
                let task = Task {
                    await startUnderstanding(photo: photo, sessionID: sessionID)
                }
                pipelineTask = task
                await task.value
            } else {
                retake()
            }
        case .story:
            if let understanding = sceneUnderstanding {
                let task = Task {
                    await startStoryWriting(understanding: understanding, sessionID: sessionID)
                }
                pipelineTask = task
                await task.value
            } else if let photo = capturedPhoto {
                let task = Task {
                    await startUnderstanding(photo: photo, sessionID: sessionID)
                }
                pipelineTask = task
                await task.value
            }
        case .imageGeneration:
            await generateStoryWorld()
        }
    }

    /// Cancel in-flight generation (and stop remote poll/upload). Returns to storyReady when possible.
    func cancelGeneration() {
        guard phase == .generating else { return }
        invalidatePipelineWork()
        generationProgress = 0
        generationStage = .preparing
        pipelineStatusText = ""
        failedStage = nil
        lastGenerationError = nil
        lastErrorMessage = nil
        if temporalStory != nil {
            phase = .storyReady
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
            phase = .viewfinder
            Task { await resumeCameraPreview() }
            dependencies.haptics.play(.selection)
        default:
            break
        }
    }

    func showOriginalNow() {
        invalidatePipelineWork()
        selectedTime = .now
        failedStage = nil
        lastGenerationError = nil
        if temporalStory != nil {
            // Prefer story gate over result when recovering from generation failure without a frame.
            phase = generatedFrame != nil ? .result : .storyReady
        } else if sceneUnderstanding != nil {
            phase = .viewfinder
            Task { await resumeCameraPreview() }
        } else {
            phase = .viewfinder
            Task { await resumeCameraPreview() }
        }
    }

    func updateTime(normalized: Double) {
        selectedTime = TimePosition(normalized: normalized)
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

    /// Minimal `fumira://` deep link. Hosts: `share`, `result`. No backend inventing.
    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "fumira" else { return }
        let host = (url.host ?? url.pathComponents.dropFirst().first)?.lowercased()
        switch host {
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
        Task { await resumeCameraPreview() }
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
    }

    private func resumeCameraPreview() async {
        do {
            try await dependencies.camera.startPreview()
            await refreshCameraControls()
        } catch {
            lastErrorMessage = error.localizedDescription
            lastGenerationError = Self.classify(error)
            failedStage = .capture
            phase = .pipelineFailure
        }
    }

    private func clearPipelineResult() {
        capturedTargetTime = nil
        capturedPhoto = nil
        sceneUnderstanding = nil
        temporalStory = nil
        generatedFrame = nil
        previousGeneratedFrame = nil
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
}

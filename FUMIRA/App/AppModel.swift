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
    /// Exact-target story work happens before the image pipeline starts, but
    /// still belongs to that same user request and must be cancellable.
    private var targetBeatTask: Task<StoryBeat, Error>?
    private var targetBeatRequestID: UUID?
    private var failedBrowsedTargetTime: TimePosition?
    /// Keeps repeated viewfinder entries from racing camera-session startup.
    private var cameraPreviewTask: Task<Void, Never>?
    /// Coalesces rapid pinch / Camera Control updates before publishing to ActivityKit.
    private var cameraActivityUpdateTask: Task<Void, Never>?
    private var cameraActivityFeedbackTask: Task<Void, Never>?

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
    var resultRevealProgress: CGFloat = 0
    var isRealityAlignmentPresented = false
    var pipelineStatusText = ""
    var hardwareSnapshot: HardwareSnapshot?
    var activeSessionID: UUID?
    var capturedPhoto: CapturedPhoto?
    var temporalCapturePacket: TemporalCapturePacket?
    /// Pre-decoded capture for the persistent hero — never decode in View bodies.
    var decodedCapturedImage: UIImage?
    /// Optional local Vision alpha mask for the same persistent hero.
    var decodedForegroundMask: UIImage?
    /// Bounded low-resolution frames around the shutter for reality inspection.
    var decodedMicroTimeSliceFrames: [UIImage] = []
    /// Pre-decoded generated frame for Result / hero crossfade.
    var decodedGeneratedImage: UIImage?
    /// Bumps when the Root shutter-flash overlay should fire.
    var shutterFlashRequestID: UUID?
    var cameraAspectRatio: CameraAspectRatio = .classic
    var narrativeSubjectAnchor: TemporalSubjectAnchor?
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
    private var didPlayResultRevealHaptic = false
    var failedStage: PipelineStage?
    var lastErrorMessage: String?
    var lastGenerationError: GenerationError?
    var posterURL: URL?
    /// Cached composed poster PNG for ShareLink / album save.
    var shareImageData: Data?
    var isPreparingPoster = false
    var isSavingPoster = false
    /// Keeps a browsed-time request single-flight while the relay writes its
    /// exact target beat. Result UI uses this for honest progress feedback.
    var isPreparingBrowsedTimeGeneration = false
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
    var cameraActivityFeedback: String?
    /// Smoothed live Vision observation used only by the lightweight viewfinder
    /// focus overlay. The capture pipeline receives its center as the narrative
    /// subject anchor without requiring a manual tap.
    var cameraTrackedSubject: CameraTrackedSubject?
    let motionField: MotionFieldModel
    let captureMotion: CaptureMotionModel
    let temporalDarkroom: TemporalDarkroomModel
    let temporalShake: TemporalShakeModel
    let blowReveal: BlowRevealModel
    /// Switches for the time interactions that lost the convergence decision.
    let experimental: ExperimentalFeatureStore
    /// A stable preview identity prevents remounting the SwiftUI/UIKit bridge
    /// whenever unrelated camera chrome state changes.
    let cameraPreview: AnyView

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        cameraPreview = dependencies.cameraPreview.makePreview()
        experimental = ExperimentalFeatureStore()
        motionField = MotionFieldModel(service: dependencies.motionField)
        captureMotion = CaptureMotionModel(
            service: dependencies.captureMotion,
            haptics: dependencies.haptics
        )
        temporalDarkroom = TemporalDarkroomModel(
            service: dependencies.temporalDarkroom
        )
        temporalShake = TemporalShakeModel(
            service: dependencies.temporalShake
        )
        blowReveal = BlowRevealModel(service: dependencies.blowInput)
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

    private var cameraSubjectTrackingProvider: (any CameraSubjectTrackingProviding)? {
        dependencies.camera as? any CameraSubjectTrackingProviding
    }

    var temporalShakeResponderService: DeviceTemporalShakeService? {
        dependencies.temporalShake as? DeviceTemporalShakeService
    }

    var isPipelineBusy: Bool {
        if isPreparingBrowsedTimeGeneration {
            return true
        }
        return switch phase {
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
        guard let narrative = temporalStory?.narrative(for: selectedTime) else {
            return "同一处现实，抵达另一个时间。"
        }
        return StoryCopyPolicy.removingRepeatedTimePrefix(
            from: narrative,
            time: selectedTime
        )
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
            phase = .viewfinder
            scheduleCameraPreview()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func prewarmCameraPreviewIfAuthorized() async {
        guard let prewarmer = dependencies.camera as? any CameraPreviewPrewarming else {
            return
        }
        await prewarmer.prewarmPreviewIfAuthorized()
    }

    func beginCameraSubjectTracking() {
        guard let provider = cameraSubjectTrackingProvider else { return }
        provider.setSubjectTrackingObserver { [weak self] subject in
            guard let self, self.phase == .viewfinder else { return }
            self.cameraTrackedSubject = subject
            guard let center = subject?.center else { return }
            self.narrativeSubjectAnchor = TemporalSubjectAnchor(
                normalizedX: center.x,
                normalizedY: center.y
            )
        }
    }

    func endCameraSubjectTracking() {
        cameraSubjectTrackingProvider?.setSubjectTrackingObserver(nil)
        cameraTrackedSubject = nil
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
        cameraActivityFeedbackTask?.cancel()
        do {
            try await dependencies.cameraActivity.trigger(
                with: cameraActivityState(phase: .framing)
            )
            lastErrorMessage = nil
            cameraActivityFeedback = "已显示在灵动岛"
            dependencies.haptics.play(.selection)
        } catch let error as CameraLiveActivityError {
            lastErrorMessage = error.localizedDescription
            cameraActivityFeedback = error.localizedDescription
            dependencies.haptics.play(.selection)
        } catch {
            let message = "无法显示灵动岛：\(error.localizedDescription)"
            lastErrorMessage = message
            cameraActivityFeedback = message
            dependencies.haptics.play(.selection)
        }
        cameraActivityFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.cameraActivityFeedback = nil
        }
    }

    func playShutterPressHaptic() {
        dependencies.haptics.play(.shutterPress)
    }

    /// Independent Root overlay flash — does not fade page content.
    func requestShutterFlash() {
        shutterFlashRequestID = UUID()
    }

    func selectNarrativeSubject(at normalizedPoint: CGPoint) {
        narrativeSubjectAnchor = TemporalSubjectAnchor(
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y
        )
        dependencies.haptics.play(.selection)
    }

    func clearNarrativeSubject() {
        guard narrativeSubjectAnchor != nil else { return }
        narrativeSubjectAnchor = nil
        dependencies.haptics.play(.selection)
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
        let shutterDate = Date()
        let sceneLayerAnalyzer = dependencies.sceneLayerAnalyzer
        dependencies.haptics.play(.shutter)

        let task = Task {
            [sessionID, composition, shutterDate, sceneLayerAnalyzer] in
            do {
                let photo = try PhotoImportAdapter.makeCapturedPhoto(
                    from: imageData,
                    composition: composition
                )
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                async let visualContext = sceneLayerAnalyzer.analyze(
                    photo: photo
                )

                let decoded = await Self.decodeForDisplay(photo.data)
                guard !Task.isCancelled, activeSessionID == sessionID else { return }

                capturedPhoto = photo
                temporalCapturePacket = TemporalCapturePacket(
                    photo: photo,
                    origin: .photoLibrary,
                    composition: composition,
                    shutterDate: shutterDate,
                    motion: .unavailable
                )
                decodedCapturedImage = decoded
                await dependencies.camera.stopPreview()
                phase = .shuttered

                let resolvedVisualContext = await visualContext
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                decodedForegroundMask = await Self.decodeForDisplay(
                    resolvedVisualContext.foregroundMaskPNG
                )
                temporalCapturePacket = TemporalCapturePacket(
                    photo: photo,
                    origin: .photoLibrary,
                    composition: composition,
                    shutterDate: shutterDate,
                    motion: .unavailable,
                    visualContext: resolvedVisualContext
                )

                // One semantic still hold; the root-owned capture timeline
                // animates the object itself and can be interrupted by cancel.
                try await Task.sleep(for: .seconds(PosterMotion.capturePresentationHold))
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
        let shutterDate = Date()
        let motionContext = captureMotion.makeContext()
        let subjectAnchor = narrativeSubjectAnchor
        let sceneLayerAnalyzer = dependencies.sceneLayerAnalyzer
        let opticalContext = await sampleOpticalContext()
        dependencies.haptics.play(.shutter)
        requestShutterFlash()
        await dependencies.cameraActivity.update(
            with: cameraActivityState(phase: .capturing)
        )

        let task = Task {
            [
                sessionID,
                composition,
                shutterDate,
                motionContext,
                subjectAnchor,
                sceneLayerAnalyzer,
                opticalContext,
            ] in
            do {
                async let microTimeSlice = sampleMicroTimeSlice(
                    around: shutterDate
                )
                let photo = try await dependencies.camera.capturePhoto(composition: composition)
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                async let visualContext = sceneLayerAnalyzer.analyze(
                    photo: photo
                )

                // Decode off the main render path before committing UI state.
                let decoded = await Self.decodeForDisplay(photo.data)
                guard !Task.isCancelled, activeSessionID == sessionID else { return }

                capturedPhoto = photo
                temporalCapturePacket = TemporalCapturePacket(
                    photo: photo,
                    origin: .camera,
                    composition: composition,
                    shutterDate: shutterDate,
                    motion: motionContext,
                    subjectAnchor: subjectAnchor,
                    opticalContext: opticalContext
                )
                decodedCapturedImage = decoded
                await updateLiveActivity(
                    phase: .captured,
                    progress: 0
                )
                // Freeze at the exact crop. RootView owns the continuous
                // lift/landing interpolation, not this business task.
                phase = .shuttered

                let (resolvedMicroTimeSlice, resolvedVisualContext) = await (
                    microTimeSlice,
                    visualContext
                )
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                async let foregroundMask = Self.decodeForDisplay(
                    resolvedVisualContext.foregroundMaskPNG
                )
                async let sliceFrames = Self.decodeMicroTimeSlice(
                    resolvedMicroTimeSlice
                )
                decodedForegroundMask = await foregroundMask
                decodedMicroTimeSliceFrames = await sliceFrames
                temporalCapturePacket = TemporalCapturePacket(
                    photo: photo,
                    origin: .camera,
                    composition: composition,
                    shutterDate: shutterDate,
                    motion: motionContext,
                    microTimeSlice: resolvedMicroTimeSlice,
                    subjectAnchor: subjectAnchor,
                    visualContext: resolvedVisualContext,
                    opticalContext: opticalContext
                )
                await dependencies.camera.stopPreview()

                // The only intentional pause is a semantic still hold. It
                // gives the user a captured frame while the visual timeline is
                // continuously driven by RootView.captureProgress.
                try await Task.sleep(for: .seconds(PosterMotion.capturePresentationHold))
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

    private func sampleMicroTimeSlice(
        around shutterDate: Date
    ) async -> MicroTimeSlice {
        guard let sampler = dependencies.camera as? any TemporalCameraSampling else {
            return .unavailable
        }
        return await sampler.microTimeSlice(around: shutterDate)
    }

    private func sampleOpticalContext() async -> TemporalOpticalContext {
        guard let provider = dependencies.camera as? any CameraOpticalContextProviding else {
            return .unavailable
        }
        return await provider.opticalContext()
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
        story: TemporalStory? = nil,
        futureFork: TemporalFutureForkBranch? = nil
    ) async {
        guard let option = modelOption(for: .image) else {
            presentConfigurationFailure()
            return
        }

        generationProgress = 0
        generationStage = .preparing
        pipelineStatusText = "前往\(targetTime.compactLabel)"
        failedStage = nil
        lastGenerationError = nil
        lastErrorMessage = nil
        phase = .generating
        await updateLiveActivity(phase: .generating, progress: 0)

        let resolvedUnderstanding = understanding ?? sceneUnderstanding
        let resolvedStory = story ?? temporalStory
        let baseBeat = resolvedStory?.generationBeat(for: targetTime)
        let resolvedBeat: StoryBeat?
        if let futureFork {
            guard let baseBeat,
                  let forkedBeat = futureFork.applying(
                    to: baseBeat,
                    target: targetTime
                  ) else {
                presentFailure(
                    stage: .imageGeneration,
                    error: GenerationError.invalidParameters,
                    sessionID: sessionID
                )
                return
            }
            resolvedBeat = forkedBeat
        } else {
            resolvedBeat = baseBeat
        }
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
                    tier: modelConfiguration.tier,
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
                    scheduleLiveActivityUpdate(
                        phase: .generating,
                        progress: value
                    )
                case let .completed(frame):
                    guard
                        frame.sessionID == sessionID,
                        targetTime.hasSameExactTimeIdentity(
                            asOffsetDays: frame.time.offsetDays
                        )
                    else {
                        throw GenerationError.generationFailed(
                            message: "目标照片的时间没有对齐，请重新生成这一帧。"
                        )
                    }
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
                    if futureFork != nil || frame.storyBeatID == nil {
                        completedFrame = GeneratedFrame(
                            id: frame.id,
                            sessionID: frame.sessionID,
                            time: frame.time,
                            storyBeatID: frame.storyBeatID ?? resolvedBeat?.id,
                            futureForkID: futureFork?.id ?? frame.futureForkID,
                            futureForkTitle: futureFork?.title ?? frame.futureForkTitle,
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
                    pipelineStatusText = "已经抵达"
                    prepareResultReveal()
                    phase = .result
                    await finishLiveActivity(phase: .ready, progress: 1)
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
        pipelineStatusText = "读取场景"
        phase = .understanding
        await updateLiveActivity(phase: .understanding, progress: 0)

        do {
            let events = await dependencies.understanding.analyze(
                request: ImageUnderstandingRequest(
                    photo: photo,
                    targetTime: targetTime,
                    sessionID: sessionID,
                    model: option,
                    narrativeAnchor: temporalCapturePacket?.subjectAnchor,
                    opticalContext: temporalCapturePacket?.opticalContext
                        ?? .unavailable
                )
            )
            for try await event in events {
                guard !Task.isCancelled, activeSessionID == sessionID else { return }
                switch event {
                case let .progress(label, value):
                    pipelineStatusText = label
                    understandingProgress = value
                    scheduleLiveActivityUpdate(
                        phase: .understanding,
                        progress: value
                    )
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
        pipelineStatusText = "连接变化"
        phase = .storyWriting
        await updateLiveActivity(phase: .storyWriting, progress: 0)

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
                    scheduleLiveActivityUpdate(
                        phase: .storyWriting,
                        progress: value
                    )
                case let .completed(value):
                    storyProgress = 1
                    temporalStory = value
                    let photo = sourcePhoto ?? capturedPhoto
                    guard let photo else {
                        pipelineStatusText = "已经抵达"
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

    /// Generates an evidence-backed alternative at the exact time of the
    /// current result. Selection and shaking stay read-only; only this explicit
    /// confirmation starts work. The original capture remains the sole image
    /// source so repeated branches cannot accumulate generation drift.
    func generateFutureFork(_ branch: TemporalFutureForkBranch) async {
        guard
            phase == .result,
            !isPipelineBusy,
            generatedFrame?.futureForkID != branch.id,
            let photo = capturedPhoto,
            let currentFrame = generatedFrame,
            let understanding = sceneUnderstanding,
            let story = temporalStory,
            currentFrame.time.offsetDays > 0,
            let baseBeat = story.generationBeat(for: currentFrame.time),
            branch.applying(to: baseBeat, target: currentFrame.time) != nil
        else {
            return
        }

        preserveCurrentResultForUndo()
        invalidatePipelineWork()
        let sessionID = UUID()
        let targetTime = currentFrame.time
        activeSessionID = sessionID
        capturedTargetTime = targetTime
        selectedTime = targetTime
        // Leave the result surface before clearing its mounted frame. This
        // prevents a render pass where ResultView is still visible but its
        // generated image and reveal state have already been reset.
        phase = .generating
        prepareForNewTargetResult()

        let task = Task {
            await startImageGeneration(
                photo: photo,
                targetTime: targetTime,
                sessionID: sessionID,
                understanding: understanding,
                story: story,
                futureFork: branch
            )
        }
        pipelineTask = task
        await task.value
    }

    /// Deliberate exploration strategy: promote the story browser's current
    /// year to a new generation target. Fetches a fresh exact target beat
    /// from the server so the generation uses the precise visual changes
    /// for this year — not the nearest canonical beat.
    func generateAtStoryPreviewTime() async {
        guard
            phase == .result,
            !isPipelineBusy,
            let sourcePhotoID = capturedPhoto?.id,
            let sourceFrameID = generatedFrame?.id,
            let understanding = sceneUnderstanding,
            let story = temporalStory
        else {
            return
        }
        // Freeze the explicit tap target before awaiting the story service. The
        // result rail remains browsable while this request is in flight, so
        // reading selectedTime again after the await can otherwise combine an
        // exact beat for time A with an image request for time B.
        let requestedTime = selectedTime
        let requestID = UUID()
        failedBrowsedTargetTime = nil
        targetBeatRequestID = requestID
        isPreparingBrowsedTimeGeneration = true
        let task = Task {
            try await dependencies.story.writeTargetBeat(
                understanding: understanding,
                story: story,
                target: requestedTime
            )
        }
        targetBeatTask = task
        // Fetch a new exact target beat for the browse year.
        do {
            let exactBeat = try await task.value
            // Ignore a stale response if the user left Result or another result
            // replaced the source frame while the exact beat was being written.
            guard
                targetBeatRequestID == requestID,
                phase == .result,
                capturedPhoto?.id == sourcePhotoID,
                generatedFrame?.id == sourceFrameID
            else {
                finishTargetBeatRequest(requestID)
                return
            }
            guard
                let exactTarget = exactBeat.exactTarget,
                requestedTime.hasSameExactTimeIdentity(
                    asOffsetDays: exactTarget.offsetDays
                )
            else {
                throw GenerationError.generationFailed(
                    message: "目标时间没有对齐，请重新生成这一帧。"
                )
            }
            // Inject the exact beat into the story for this generation.
            temporalStory = TemporalStory(
                title: story.title,
                logline: story.logline,
                presentTruth: story.presentTruth,
                identityRules: story.identityRules,
                beats: story.beats,
                targetBeat: exactBeat
            )
            capturedTargetTime = requestedTime
            selectedTime = requestedTime
            failedBrowsedTargetTime = nil
            finishTargetBeatRequest(requestID)
            await generateStoryWorld()
        } catch is CancellationError {
            finishTargetBeatRequest(requestID)
            return
        } catch {
            guard
                targetBeatRequestID == requestID,
                phase == .result,
                capturedPhoto?.id == sourcePhotoID,
                generatedFrame?.id == sourceFrameID
            else {
                finishTargetBeatRequest(requestID)
                return
            }
            failedBrowsedTargetTime = requestedTime
            finishTargetBeatRequest(requestID)
            failedStage = .story
            let classified = Self.classify(error)
            lastGenerationError = classified
            lastErrorMessage = classified.errorDescription ?? error.localizedDescription
            phase = .pipelineFailure
        }
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

        if stage == .story,
           let failedBrowsedTargetTime,
           generatedFrame != nil,
           sceneUnderstanding != nil,
           temporalStory != nil {
            failedStage = nil
            lastErrorMessage = nil
            lastGenerationError = nil
            phase = .result
            selectedTime = failedBrowsedTargetTime
            await generateAtStoryPreviewTime()
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
        dismissLiveActivity()
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
            dismissLiveActivity()
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
        dismissLiveActivity()
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

    func syncCaptureMotion(for phase: AppPhase, sceneIsActive: Bool) {
        let keepsRealitySpatiallyResponsive: Bool
        switch phase {
        case .viewfinder, .shuttered, .understanding, .storyWriting, .generating,
             .result:
            keepsRealitySpatiallyResponsive = true
        default:
            keepsRealitySpatiallyResponsive = false
        }
        captureMotion.setAnchorFeedbackEnabled(phase == .viewfinder)
        guard keepsRealitySpatiallyResponsive, sceneIsActive else {
            captureMotion.deactivate()
            return
        }
        captureMotion.activate()
    }

    /// The top-screen covering ritual was removed from the product flow.
    /// Keep this seam so the root lifecycle remains explicit, but never start
    /// proximity monitoring for a design that no longer has a visible action.
    func syncTemporalDarkroom(
        for _: AppPhase,
        reduceMotion _: Bool,
        sceneIsActive _: Bool
    ) {
        temporalDarkroom.deactivate()
    }

    /// Shake is an opt-in branch selector for future results. It is short-lived,
    /// has a button fallback, and cannot mutate time or start generation.
    func syncTemporalShake(
        for phase: AppPhase,
        reduceMotion: Bool,
        sceneIsActive: Bool
    ) {
        temporalShake.setSceneActive(sceneIsActive)
        guard experimental.isEnabled(.shakeToFork),
              experimental.isEnabled(.futureFork) else {
            temporalShake.deactivate()
            return
        }
        let target = generatedFrame?.time ?? generationTargetTime
        let branches = TemporalFutureForkEngine.resolve(
            understanding: sceneUnderstanding,
            target: target
        ).branches
        guard phase == .result,
              sceneIsActive,
              target.offsetDays > 0,
              branches.count >= 2 else {
            temporalShake.deactivate()
            return
        }
        temporalShake.activate(reduceMotion: reduceMotion)
    }

    func playFutureForkDetent() {
        dependencies.haptics.play(.selection)
    }

    func prepareResultReveal() {
        blowReveal.reset()
        resultRevealProgress = 0
        didPlayResultRevealHaptic = false
        isRealityAlignmentPresented = false
    }

    func updateResultRevealProgress(_ progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        guard abs(clamped - resultRevealProgress) > 0.002 else { return }
        resultRevealProgress = clamped
        if clamped >= 1, !didPlayResultRevealHaptic {
            didPlayResultRevealHaptic = true
            dependencies.haptics.play(.reveal)
        }
    }

    func completeResultReveal() {
        blowReveal.deactivate()
        updateResultRevealProgress(1)
    }

    /// Re-enters the camera without changing the result phase so the generated
    /// time can be compared against the live world. Failure is deliberately
    /// non-fatal: the comparison surface falls back to the captured still.
    func startRealityAlignment() async -> Bool {
        do {
            try await dependencies.camera.startPreview()
            lastErrorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            lastErrorMessage = "实时相机不可用，已改用原片。"
            return false
        }
    }

    func stopRealityAlignment() async {
        await dependencies.camera.stopPreview()
    }

    func playRealityAlignmentLockHaptic() {
        dependencies.haptics.play(.timeAnchor)
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
        // A prior poster may belong to a different browsed or generated time.
        // Clear it before the share sheet can expose stale bytes.
        shareImageData = nil
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
        case "progress":
            // Live Activity tap during developing — bring the person back to
            // whatever developing stage is already on screen.
            break
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
            let time = posterTime
            let snapshot = PosterSnapshot(
                time: time,
                title: temporalStory?.title ?? currentStoryBeat?.title ?? "这一刻的时间故事",
                yearLabel: PosterComposer.yearLabel(for: time),
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

    /// Posters are artifacts of the frame that actually exists. Browsing the
    /// rail may change `selectedTime`, but it cannot relabel old image bytes.
    private var posterTime: TimePosition {
        generatedFrame?.time ?? generationTargetTime
    }

    private func composePosterPNG() throws -> Data {
        let time = posterTime
        let trace = TemporalInterpretationTrace.resolve(
            story: temporalStory,
            understanding: sceneUnderstanding,
            at: time
        )
        return try PosterComposer.renderPNG(
            time: time,
            yearLabel: PosterComposer.yearLabel(for: time),
            title: temporalStory?.title ?? currentStoryBeat?.title ?? "这一刻的时间故事",
            narrative: StoryCopyPolicy.removingRepeatedTimePrefix(
                from: trace.narrative,
                time: time
            ),
            sceneImageData: generatedFrame?.imageData,
            interpretationTrace: trace
        )
    }

    func retake() {
        invalidatePipelineWork()
        dismissLiveActivity()
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
            lastErrorMessage = "这个模型尚未接入。"
            return
        }
        modelConfiguration.select(optionID: optionID, for: role)
        do {
            try await dependencies.modelConfigurationStore.save(modelConfiguration)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "本次已生效，暂时无法保存。"
        }
    }

    /// The primary quality control. Moves the image model with the tier so the
    /// two can never disagree, and keeps a manual model override from silently
    /// claiming a tier it does not match.
    func selectTier(_ tier: GenerationTier) async {
        guard modelCatalog.option(id: tier.imageOptionID)?.availability == .ready else {
            lastErrorMessage = "这个档位的模型尚未接入。"
            return
        }
        modelConfiguration.select(tier: tier)
        do {
            try await dependencies.modelConfigurationStore.save(modelConfiguration)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "本次已生效，暂时无法保存。"
        }
    }

    /// True when the image model still matches the tier it was selected from.
    /// A manual override in advanced settings makes this false, and the UI
    /// surfaces that rather than pretending the tier is still authoritative.
    var isTierImageModelOverridden: Bool {
        modelConfiguration.imageOptionID != modelConfiguration.tier.imageOptionID
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
        finishLiveActivity(phase: .failed, progress: nil)
        failedStage = .configuration
        lastGenerationError = nil
        lastErrorMessage = "模型未接通。请在设置 → 高级中更换。"
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
        finishLiveActivity(phase: .failed, progress: nil)
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
        targetBeatTask?.cancel()
        targetBeatTask = nil
        targetBeatRequestID = nil
        isPreparingBrowsedTimeGeneration = false
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
        scheduleLiveActivityUpdate(phase: .framing, progress: nil)
    }

    private func scheduleLiveActivityUpdate(
        phase: CameraLiveActivityAttributes.ContentState.Phase,
        progress: Double?
    ) {
        let state = cameraActivityState(phase: phase, progress: progress)
        let cameraActivity = dependencies.cameraActivity
        cameraActivityUpdateTask?.cancel()
        cameraActivityUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await cameraActivity.update(with: state)
        }
    }

    private func updateLiveActivity(
        phase: CameraLiveActivityAttributes.ContentState.Phase,
        progress: Double?
    ) async {
        cameraActivityUpdateTask?.cancel()
        cameraActivityUpdateTask = nil
        await dependencies.cameraActivity.update(
            with: cameraActivityState(phase: phase, progress: progress)
        )
    }

    private func finishLiveActivity(
        phase: CameraLiveActivityAttributes.ContentState.Phase,
        progress: Double?
    ) async {
        cameraActivityUpdateTask?.cancel()
        cameraActivityUpdateTask = nil
        await dependencies.cameraActivity.finish(
            with: cameraActivityState(phase: phase, progress: progress)
        )
    }

    private func finishLiveActivity(
        phase: CameraLiveActivityAttributes.ContentState.Phase,
        progress: Double?
    ) {
        cameraActivityUpdateTask?.cancel()
        cameraActivityUpdateTask = nil
        let state = cameraActivityState(phase: phase, progress: progress)
        let cameraActivity = dependencies.cameraActivity
        Task {
            await cameraActivity.finish(with: state)
        }
    }

    private func dismissLiveActivity() {
        cameraActivityUpdateTask?.cancel()
        cameraActivityUpdateTask = nil
        let cameraActivity = dependencies.cameraActivity
        Task {
            await cameraActivity.dismissAll()
        }
    }

    private func cameraActivityState(
        phase: CameraLiveActivityAttributes.ContentState.Phase,
        progress: Double? = nil
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
            aspectRatioLabel: cameraAspectRatio.label,
            progress: progress
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
        temporalDarkroom.reset()
        temporalShake.deactivate()
        blowReveal.reset()
        generatedFrame = nil
        generatedPhoto = nil
        decodedGeneratedImage = nil
        cameraActivityFeedback = nil
        cameraActivityFeedbackTask?.cancel()
        // Keep Scene Bible + story across regenerations so every target year
        // reuses the same source understanding (no chain drift).
        understandingProgress = 0
        storyProgress = 0
        generationProgress = 0
        generationStage = .preparing
        resultRevealProgress = 0
        didPlayResultRevealHaptic = false
        isRealityAlignmentPresented = false
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
        temporalDarkroom.reset()
        temporalShake.deactivate()
        blowReveal.reset()
        failedBrowsedTargetTime = nil
        capturedTargetTime = nil
        capturedPhoto = nil
        temporalCapturePacket = nil
        decodedCapturedImage = nil
        decodedForegroundMask = nil
        decodedMicroTimeSliceFrames = []
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
        resultRevealProgress = 0
        didPlayResultRevealHaptic = false
        isRealityAlignmentPresented = false
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

    private func finishTargetBeatRequest(_ requestID: UUID) {
        guard targetBeatRequestID == requestID else { return }
        targetBeatTask = nil
        targetBeatRequestID = nil
        isPreparingBrowsedTimeGeneration = false
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

    private static func decodeMicroTimeSlice(
        _ slice: MicroTimeSlice
    ) async -> [UIImage] {
        let samples = slice.frames
        guard !samples.isEmpty else { return [] }
        return await Task.detached(priority: .utility) {
            samples.compactMap { sample in
                guard let image = UIImage(data: sample.jpegData) else { return nil }
                return image.preparingForDisplay() ?? image
            }
        }.value
    }
}

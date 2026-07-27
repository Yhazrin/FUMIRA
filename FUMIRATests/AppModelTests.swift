import XCTest
import UIKit
@testable import FUMIRA

@MainActor
final class AppModelTests: XCTestCase {
    func testPhoneOnlyPathReachesViewfinder() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        XCTAssertEqual(model.phase, .cameraPermission)
        await model.grantCameraAccess()
        XCTAssertEqual(model.phase, .viewfinder)
    }

    func testSimulatorDependenciesUseSafeCameraFallback() {
        #if targetEnvironment(simulator)
        let model = AppModel(dependencies: .runtime)
        XCTAssertFalse(model.isUsingLiveCamera)
        XCTAssertFalse(model.hasLiveCameraControls)
        #endif
    }

    func testMockCameraHidesUnsupportedLiveControls() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        XCTAssertFalse(model.hasLiveCameraControls)
        XCTAssertFalse(model.canSwitchCamera)
        XCTAssertFalse(model.supportsCameraFlash)
        model.toggleCameraGrid()
        XCTAssertTrue(model.isCameraGridEnabled)
    }

    func testHardwarePathReachesCameraPermission() async {
        let model = AppModel(dependencies: .test)
        model.beginHardwarePath()
        XCTAssertEqual(model.phase, .bluetoothPermission)
        await model.grantBluetoothAndConnect()
        XCTAssertEqual(model.phase, .connected)
        XCTAssertEqual(model.hardwareSnapshot?.batteryLevel, 86)
        model.continueFromConnection()
        XCTAssertEqual(model.phase, .cameraPermission)
    }

    func testRetakeCancelsSessionAndReturnsToViewfinder() {
        let model = AppModel(dependencies: .test)
        model.activeSessionID = UUID()
        model.presentFailureForPreview()
        XCTAssertEqual(model.phase, .pipelineFailure)
        XCTAssertNil(model.activeSessionID)
        model.retake()
        XCTAssertEqual(model.phase, .viewfinder)
        XCTAssertNil(model.activeSessionID)
    }

    func testCaptureCompletesTargetPhotoFirstPipelineWithoutReviewGate() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()

        await model.capture()

        XCTAssertEqual(model.phase, .result)
        XCTAssertNotNil(model.capturedPhoto)
        XCTAssertNotNil(model.capturedPhoto.flatMap { UIImage(data: $0.data) })
        XCTAssertNotNil(model.generatedFrame)
        XCTAssertNotNil(model.generatedPhoto)
        XCTAssertNotNil(model.generatedFrame?.imageData)
        XCTAssertNotNil(model.sceneUnderstanding)
        XCTAssertNotNil(model.temporalStory)
        XCTAssertEqual(model.generationProgress, 1)
        XCTAssertEqual(model.understandingProgress, 1)
        XCTAssertEqual(model.storyProgress, 1)
    }

    func testPipelineOrdersSourceUnderstandingAndStoryBeforeGeneration() async {
        let trace = PipelineTrace()
        let generatedData = makeTestJPEG(width: 900, height: 900)
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: TracingUnderstandingProvider(trace: trace),
            story: TracingStoryProvider(trace: trace),
            generation: TracingGenerationProvider(
                trace: trace,
                outputData: generatedData
            ),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()

        await model.capture()

        let snapshot = await trace.snapshot()
        XCTAssertEqual(snapshot.steps, [.understanding, .story, .generation])
        XCTAssertEqual(snapshot.analyzedImageData, model.capturedPhoto?.data)
        XCTAssertEqual(model.generatedPhoto?.data, generatedData)
        XCTAssertEqual(model.phase, .result)
    }

    func testCaptureLocksTimeAndUsesServerAuthoredPromptFallbackOnMock() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        model.updateTime(normalized: 0.8)
        await model.capture()

        XCTAssertEqual(model.phase, .result)
        XCTAssertEqual(model.generatedFrame?.sessionID, model.activeSessionID)
        XCTAssertEqual(model.generatedFrame?.modelOptionID, "fumira.image.identity")
        XCTAssertEqual(model.generatedFrame?.time, model.capturedTargetTime)
        XCTAssertTrue(model.generatedFrame?.prompt.contains("mock-fallback") == true)
        XCTAssertTrue(model.generatedFrame?.prompt.contains("不能在改变一个主体后停止") == true)
        XCTAssertNotNil(model.generatedFrame?.storyBeatID)
        XCTAssertNotNil(model.sceneUnderstanding)
        XCTAssertNotNil(model.temporalStory)
    }

    func testStoryNarrativeChangesAcrossTime() {
        let story = TemporalStory.parkReference
        let past = story.narrative(for: TimePosition(offsetDays: -36_525))
        let present = story.narrative(for: .now)
        let future = story.narrative(for: TimePosition(offsetDays: 36_525))

        XCTAssertNotEqual(past, present)
        XCTAssertNotEqual(present, future)
        XCTAssertNotEqual(past, future)
    }

    func testMockFallbackPromptStaysShortAndPanoramic() {
        let prompt = TemporalImagePrompt.make(
            for: TimePosition(offsetDays: 20 * 365.25)
        )

        XCTAssertTrue(prompt.contains("mock-fallback"))
        XCTAssertTrue(prompt.contains("未来方向"))
        XCTAssertTrue(prompt.contains("不能在改变一个主体后停止"))
        XCTAssertTrue(prompt.contains("无关、抢镜或缺乏时间因果依据"))
        XCTAssertLessThanOrEqual(prompt.count, 280)
    }

    func testResultPhotoGeometryPreservesAspectRatioWithinAvailableStage() {
        let portrait = ResultLayoutGeometry.photoSize(
            in: CGSize(width: 402, height: 874),
            safeAreaTop: 59,
            aspectRatio: 3.0 / 4.0
        )
        let landscape = ResultLayoutGeometry.photoSize(
            in: CGSize(width: 402, height: 874),
            safeAreaTop: 59,
            aspectRatio: 4.0 / 3.0
        )

        XCTAssertEqual(portrait.width / portrait.height, 3.0 / 4.0, accuracy: 0.000_001)
        XCTAssertEqual(landscape.width / landscape.height, 4.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(portrait.width, 402)
        XCTAssertEqual(landscape.width, 402)
        XCTAssertEqual(ResultLayoutGeometry.contentWidth(in: 402), 370)
    }

    func testResultLayoutKeepsPanelInsideViewportAndAllowsPhotoReveal() {
        let layout = ResultLayoutGeometry.layout(
            in: CGSize(width: 402, height: 759),
            safeAreaTop: 0,
            aspectRatio: 3.0 / 4.0
        )

        XCTAssertEqual(layout.viewportWidth, 402)
        XCTAssertEqual(layout.photoSize.width, 402)
        XCTAssertGreaterThan(layout.panelTop, 0)
        XCTAssertLessThan(layout.panelTop, 759)
        XCTAssertEqual(layout.panelTop + layout.panelHeight, 759, accuracy: 0.000_001)
        XCTAssertGreaterThan(layout.maximumPanelPull, 0)
        XCTAssertLessThanOrEqual(
            layout.maximumPanelPull,
            layout.panelHeight - 116
        )
    }

    func testResultLayoutDoesNotApplySafeAreaTopTwice() {
        let withoutReportedInset = ResultLayoutGeometry.layout(
            in: CGSize(width: 402, height: 759),
            safeAreaTop: 0,
            aspectRatio: 3.0 / 4.0
        )
        let withReportedInset = ResultLayoutGeometry.layout(
            in: CGSize(width: 402, height: 759),
            safeAreaTop: 59,
            aspectRatio: 3.0 / 4.0
        )

        XCTAssertEqual(withReportedInset.photoTop, withoutReportedInset.photoTop)
        XCTAssertEqual(withReportedInset.photoSize, withoutReportedInset.photoSize)
    }

    func testResultPrimaryActionsNeverExceedAvailableWidth() {
        let regular = ResultLayoutGeometry.primaryActionLayout(in: 370)
        XCTAssertFalse(regular.isStacked)
        XCTAssertEqual(
            regular.buttonWidth * 2 + regular.spacing,
            370,
            accuracy: 0.000_001
        )

        let compact = ResultLayoutGeometry.primaryActionLayout(in: 288)
        XCTAssertTrue(compact.isStacked)
        XCTAssertEqual(compact.buttonWidth, 288)
    }

    func testHeroSlotPreferencesRetainBothPipelineSidesOfPhaseTransition() {
        let generating = HeroSlotPreference(
            frame: CGRect(x: 80, y: 260, width: 180, height: 240),
            cornerRadius: 8
        )
        let understanding = HeroSlotPreference(
            frame: CGRect(x: 16, y: 64, width: 370, height: 493),
            cornerRadius: 8
        )
        var preferences = HeroSlotPreferenceKey.defaultValue

        HeroSlotPreferenceKey.reduce(value: &preferences) {
            [.generating: generating]
        }
        HeroSlotPreferenceKey.reduce(value: &preferences) {
            [.understanding: understanding]
        }

        XCTAssertEqual(preferences[.generating], generating)
        XCTAssertEqual(preferences[.understanding], understanding)
    }

    func testRemoteGenerationPollingOutlivesRelayTimeoutBudget() {
        XCTAssertGreaterThanOrEqual(
            RemoteGenerationProvider.defaultPollingWindowSeconds,
            420
        )
    }

    func testStoryCopyPolicyBoundsProviderTextForCurrentLayouts() {
        let longText = String(repeating: "长", count: 200)
        let story = TemporalStory(
            title: longText,
            logline: longText,
            presentTruth: longText,
            identityRules: [longText],
            beats: [
                StoryBeat(
                    anchorYears: 0,
                    title: longText,
                    narrative: longText,
                    visualPrompt: longText
                )
            ]
        )

        XCTAssertLessThanOrEqual(story.title.count, StoryCopyPolicy.title)
        XCTAssertLessThanOrEqual(story.logline.count, StoryCopyPolicy.logline)
        XCTAssertLessThanOrEqual(story.presentTruth.count, StoryCopyPolicy.presentTruth)
        XCTAssertLessThanOrEqual(story.identityRules[0].count, StoryCopyPolicy.identityRule)
        XCTAssertLessThanOrEqual(story.beats[0].title.count, StoryCopyPolicy.beatTitle)
        XCTAssertLessThanOrEqual(story.beats[0].narrative.count, StoryCopyPolicy.beatNarrative)
        XCTAssertLessThanOrEqual(story.beats[0].visualPrompt.count, StoryCopyPolicy.visualPrompt)
    }

    func testUnderstandingCopyPolicyBoundsProviderTextForCurrentLayouts() {
        let longText = String(repeating: "长", count: 200)
        let understanding = SceneUnderstanding(
            summary: longText,
            locationType: longText,
            visualMood: longText,
            timeClues: [longText],
            changeDrivers: [longText],
            subjects: [
                SceneSubject(
                    name: longText,
                    confidence: 0.9,
                    identityRule: longText
                )
            ]
        )

        XCTAssertLessThanOrEqual(understanding.summary.count, UnderstandingCopyPolicy.summary)
        XCTAssertLessThanOrEqual(understanding.locationType.count, UnderstandingCopyPolicy.locationType)
        XCTAssertLessThanOrEqual(understanding.visualMood.count, UnderstandingCopyPolicy.visualMood)
        XCTAssertLessThanOrEqual(understanding.timeClues[0].count, UnderstandingCopyPolicy.timeClue)
        XCTAssertLessThanOrEqual(understanding.changeDrivers[0].count, UnderstandingCopyPolicy.changeDriver)
        XCTAssertLessThanOrEqual(understanding.subjects[0].name.count, UnderstandingCopyPolicy.subjectName)
        XCTAssertLessThanOrEqual(understanding.subjects[0].identityRule.count, UnderstandingCopyPolicy.identityRule)
    }

    func testOnlyReadyModelRoutesCanRun() {
        let catalog = AIModelCatalog.bundled
        XCTAssertTrue(catalog.isRunnable(.standard))

        var relay = AIModelConfiguration.standard
        relay.select(optionID: "apimart.image.gpt-image-2", for: .image)
        XCTAssertTrue(catalog.isRunnable(relay))
        XCTAssertEqual(
            catalog.option(id: relay.imageOptionID)?.provider.imageGenerationRoute,
            "apimart"
        )

        var unavailable = AIModelConfiguration.standard
        unavailable.select(optionID: "openai.story.server", for: .story)
        XCTAssertFalse(catalog.isRunnable(unavailable))
    }

    func testFailurePreservesStoryAndCancelsActiveWork() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()
        let storyID = model.temporalStory?.id

        model.presentFailureForPreview()

        XCTAssertEqual(model.phase, .pipelineFailure)
        XCTAssertEqual(model.failedStage, .imageGeneration)
        XCTAssertEqual(model.lastGenerationError, .timedOut)
        XCTAssertNil(model.activeSessionID)
        XCTAssertEqual(model.temporalStory?.id, storyID)
    }

    func testCancelRegenerationRestoresPreviousResultWithoutFailure() async {
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MockGenerationProvider(stepDelay: .milliseconds(400)),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()
        XCTAssertEqual(model.phase, .result)
        let previousFrameID = model.generatedFrame?.id

        let generateTask = Task { await model.regenerateResult() }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.phase, .generating)
        model.cancelGeneration()

        await generateTask.value
        XCTAssertEqual(model.phase, .result)
        XCTAssertNil(model.activeSessionID)
        XCTAssertNil(model.failedStage)
        XCTAssertEqual(model.generatedFrame?.id, previousFrameID)
        XCTAssertEqual(model.generationProgress, 0)
    }

    func testRetryImageGenerationAfterFailureSucceeds() async {
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MockGenerationProvider(
                stepDelay: .zero,
                failureMode: .failOnce(.timedOut)
            ),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()

        XCTAssertEqual(model.phase, .pipelineFailure)
        XCTAssertEqual(model.failedStage, .imageGeneration)
        XCTAssertEqual(model.lastGenerationError, .timedOut)
        XCTAssertTrue(model.canRetryFailedStage)

        await model.retryPipeline()
        XCTAssertEqual(model.phase, .result)
        XCTAssertNotNil(model.generatedFrame)
        XCTAssertNil(model.failedStage)
    }

    func testUnderstandingFailureBeforeGenerationPresentsFailure() async {
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: FailingUnderstandingProvider(),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MockGenerationProvider(stepDelay: .zero),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()

        XCTAssertEqual(model.phase, .pipelineFailure)
        XCTAssertEqual(model.failedStage, .understanding)
        XCTAssertNil(model.generatedFrame)
        XCTAssertNil(model.temporalStory)
        XCTAssertNotNil(model.capturedPhoto)

        model.retake()

        XCTAssertEqual(model.phase, .viewfinder)
        XCTAssertNil(model.failedStage)
    }

    func testDuplicateGenerateWhileBusyIsIgnored() async {
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MockGenerationProvider(stepDelay: .milliseconds(250)),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()

        let first = Task { await model.capture() }
        try? await Task.sleep(for: .milliseconds(700))
        let sessionDuringFirst = model.activeSessionID
        XCTAssertEqual(model.phase, .generating)

        await model.generateStoryWorld()
        XCTAssertEqual(model.activeSessionID, sessionDuringFirst)

        await first.value
        XCTAssertEqual(model.phase, .result)
    }

    func testNonRetryableFailureRoutesToStoryAdjustment() async {
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MockGenerationProvider(
                stepDelay: .zero,
                failureMode: .always(.invalidParameters)
            ),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()

        XCTAssertEqual(model.lastGenerationError, .invalidParameters)
        XCTAssertFalse(model.canRetryFailedStage)

        await model.retryPipeline()
        XCTAssertEqual(model.phase, .viewfinder)
        XCTAssertNil(model.failedStage)
    }

    func testImportPhotoEntersSamePipelineAsCapture() async throws {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()

        let landscape = makeTestJPEG(width: 1_200, height: 800)
        await model.importPhoto(imageData: landscape)

        XCTAssertEqual(model.phase, .result)
        XCTAssertNotNil(model.capturedPhoto)
        XCTAssertNotNil(model.generatedPhoto)
        XCTAssertNotNil(model.sceneUnderstanding)
        XCTAssertNotNil(model.temporalStory)
        let photo = try XCTUnwrap(model.capturedPhoto)
        let ratio = Double(photo.pixelWidth) / Double(photo.pixelHeight)
        XCTAssertEqual(ratio, 4.0 / 3.0, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
    }

    func testRegenerateResultReplacesFrameAndSupportsOneUndo() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        model.updateTime(normalized: 0.7)
        await model.capture()

        let firstID = model.generatedFrame?.id
        XCTAssertEqual(model.phase, .result)
        XCTAssertNotNil(firstID)
        XCTAssertFalse(model.canUndoGeneration)

        model.updateTime(normalized: 0.9)
        await model.regenerateResult()

        XCTAssertEqual(model.phase, .result)
        XCTAssertNotEqual(model.generatedFrame?.id, firstID)
        XCTAssertTrue(model.canUndoGeneration)
        XCTAssertEqual(model.previousGeneratedFrame?.id, firstID)

        model.undoLastGeneration()

        XCTAssertEqual(model.phase, .result)
        XCTAssertEqual(model.generatedFrame?.id, firstID)
        XCTAssertFalse(model.canUndoGeneration)
    }

    private func makeTestJPEG(width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private enum PipelineTraceStep: Equatable, Sendable {
    case generation
    case understanding
    case story
}

private actor PipelineTrace {
    private var recordedSteps: [PipelineTraceStep] = []
    private var recordedAnalyzedImageData: Data?

    func record(_ step: PipelineTraceStep, analyzedImageData: Data? = nil) {
        recordedSteps.append(step)
        if let analyzedImageData {
            recordedAnalyzedImageData = analyzedImageData
        }
    }

    func snapshot() -> (steps: [PipelineTraceStep], analyzedImageData: Data?) {
        (recordedSteps, recordedAnalyzedImageData)
    }
}

private actor TracingGenerationProvider: GenerationProvider {
    let trace: PipelineTrace
    let outputData: Data

    init(trace: PipelineTrace, outputData: Data) {
        self.trace = trace
        self.outputData = outputData
    }

    func generate(
        request: ImageGenerationRequest
    ) async -> AsyncThrowingStream<GenerationEvent, Error> {
        await trace.record(.generation)
        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(GeneratedFrame(
                sessionID: request.sessionID,
                time: request.time,
                prompt: request.prompt,
                modelOptionID: request.model.id,
                imageData: outputData
            )))
            continuation.finish()
        }
    }
}

private actor TracingUnderstandingProvider: ImageUnderstandingProvider {
    let trace: PipelineTrace

    init(trace: PipelineTrace) {
        self.trace = trace
    }

    func analyze(
        request: ImageUnderstandingRequest
    ) async -> AsyncThrowingStream<UnderstandingEvent, Error> {
        await trace.record(.understanding, analyzedImageData: request.photo.data)
        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(.parkReference))
            continuation.finish()
        }
    }
}

private actor TracingStoryProvider: StoryProvider {
    let trace: PipelineTrace

    init(trace: PipelineTrace) {
        self.trace = trace
    }

    func write(
        request: StoryRequest
    ) async -> AsyncThrowingStream<StoryEvent, Error> {
        await trace.record(.story)
        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(.fallback(
                understanding: request.understanding,
                targetTime: request.targetTime
            )))
            continuation.finish()
        }
    }
}

private actor FailingUnderstandingProvider: ImageUnderstandingProvider {
    func analyze(
        request: ImageUnderstandingRequest
    ) async -> AsyncThrowingStream<UnderstandingEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: GenerationError.generationFailed(
                    message: "图片理解返回格式异常，请重试。"
                )
            )
        }
    }
}

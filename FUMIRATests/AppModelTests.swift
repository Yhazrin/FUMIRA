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
        XCTAssertTrue(model.hasLiveCameraControls)
        #endif
    }

    func testResultRevealFallbackCompletesBlowReveal() {
        let model = AppModel(dependencies: .test)
        model.prepareResultReveal()

        model.updateResultRevealProgress(0.42)
        XCTAssertEqual(model.resultRevealProgress, 0.42, accuracy: 0.001)

        model.completeResultReveal()
        XCTAssertEqual(model.resultRevealProgress, 1, accuracy: 0.001)
    }

    func testRealityAlignmentUsesCapturedAttitudeAndWrapsAngles() {
        let captured = CaptureMotionSample(
            timestamp: 1,
            roll: .pi,
            pitch: 0,
            yaw: 0,
            rotationRate: 0,
            acceleration: 0,
            stability: 1
        )

        XCTAssertEqual(
            RealityAlignmentGeometry.progress(
                currentRoll: -.pi,
                currentPitch: 0,
                currentYaw: 0,
                captured: captured
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RealityAlignmentGeometry.progress(
                currentRoll: -.pi + 0.12,
                currentPitch: 0,
                currentYaw: 0,
                captured: captured
            ),
            0.5,
            accuracy: 0.001
        )
    }

    func testMockCameraExposesFlipAndFlashControls() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        // Give the preview-startup refresh a beat to publish mock controls.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(model.hasLiveCameraControls)
        XCTAssertTrue(model.canSwitchCamera)
        XCTAssertTrue(model.supportsCameraFlash)
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

    func testCancelPipelineWorksDuringRealityUnderstanding() {
        let model = AppModel(dependencies: .test)
        model.phase = .understanding
        model.activeSessionID = UUID()
        model.understandingProgress = 0.48
        model.pipelineStatusText = "正在读取空间"

        model.cancelPipeline()

        XCTAssertEqual(model.phase, .viewfinder)
        XCTAssertNil(model.activeSessionID)
        XCTAssertEqual(model.understandingProgress, 0)
        XCTAssertTrue(model.pipelineStatusText.isEmpty)
    }

    func testCaptureCompletesTargetPhotoFirstPipelineWithoutReviewGate() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        model.selectNarrativeSubject(at: CGPoint(x: 0.27, y: 0.63))

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
        XCTAssertEqual(model.temporalCapturePacket?.origin, .camera)
        XCTAssertEqual(model.temporalCapturePacket?.composition, .classic)
        XCTAssertEqual(model.temporalCapturePacket?.microTimeSlice.frames.count, 6)
        XCTAssertTrue(model.temporalCapturePacket?.microTimeSlice.isAvailable == true)
        XCTAssertEqual(model.decodedMicroTimeSliceFrames.count, 6)
        XCTAssertTrue(model.temporalCapturePacket?.visualContext.isAvailable == true)
        XCTAssertTrue(model.temporalCapturePacket?.opticalContext.isAvailable == true)
        XCTAssertEqual(
            model.temporalCapturePacket?.opticalContext.lightCondition,
            .balanced
        )
        XCTAssertEqual(
            model.temporalCapturePacket?.visualContext.salientRegions.count,
            2
        )
        XCTAssertEqual(
            model.temporalCapturePacket?.subjectAnchor,
            TemporalSubjectAnchor(normalizedX: 0.27, normalizedY: 0.63)
        )
    }

    func testTemporalSalientRegionClampsToNormalizedBounds() {
        let region = TemporalSalientRegion(
            normalizedX: -0.4,
            normalizedY: 1.4,
            normalizedWidth: 2,
            normalizedHeight: -1
        )

        XCTAssertEqual(region.normalizedX, 0)
        XCTAssertEqual(region.normalizedY, 1)
        XCTAssertEqual(region.normalizedWidth, 1)
        XCTAssertEqual(region.normalizedHeight, 0)
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
        XCTAssertEqual(model.generatedFrame?.modelOptionID, GenerationTier.default.imageOptionID)
        XCTAssertEqual(model.generatedFrame?.time, model.capturedTargetTime)
        XCTAssertTrue(model.generatedFrame?.prompt.contains("mock-fallback") == true)
        XCTAssertTrue(model.generatedFrame?.prompt.contains("不能在改变一个主体后停止") == true)
        XCTAssertNotNil(model.generatedFrame?.storyBeatID)
        XCTAssertNotNil(model.sceneUnderstanding)
        XCTAssertNotNil(model.temporalStory)
    }

    func testGeneratingAtAnotherBrowsedTimeSendsThatExactTimeAndReturnsItsImage() async throws {
        let firstImageData = makeTestJPEG(width: 900, height: 1_200)
        let secondImageData = makeTestJPEG(width: 1_200, height: 900)
        let generation = TimeRecordingGenerationProvider(
            outputDataByRequest: [firstImageData, secondImageData]
        )
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        let firstTime = TimePosition(offsetDays: -1_234.5)
        let secondTime = TimePosition(offsetDays: 8_765.25)

        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        model.updateTime(normalized: firstTime.normalized)
        await model.capture()

        let firstFrameID = try XCTUnwrap(model.generatedFrame?.id)
        model.updateTime(normalized: secondTime.normalized)
        await model.generateAtStoryPreviewTime()

        let requestedTimes = await generation.requestedTimes()
        XCTAssertEqual(requestedTimes.count, 2)
        XCTAssertEqual(requestedTimes[0].offsetDays, firstTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(requestedTimes[1].offsetDays, secondTime.offsetDays, accuracy: 0.001)
        let capturedTargetTime = try XCTUnwrap(model.capturedTargetTime)
        let generatedFrame = try XCTUnwrap(model.generatedFrame)
        let exactTarget = try XCTUnwrap(model.temporalStory?.targetBeat?.exactTarget)
        XCTAssertEqual(capturedTargetTime.offsetDays, secondTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(generatedFrame.time.offsetDays, secondTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(
            exactTarget.offsetDays,
            secondTime.offsetDays,
            accuracy: 0.001
        )
        XCTAssertNotEqual(generatedFrame.id, firstFrameID)
        XCTAssertEqual(generatedFrame.imageData, secondImageData)
        XCTAssertNotNil(generatedFrame.imageData.flatMap(UIImage.init(data:)))
        XCTAssertEqual(model.phase, .result)
    }

    func testBrowsedTimeGenerationKeepsTapTimeWhenRailMovesDuringExactBeatRequest() async throws {
        let story = GatedTargetBeatStoryProvider()
        let generation = TimeRecordingGenerationProvider(
            outputData: makeTestJPEG(width: 900, height: 1_200)
        )
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: story,
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        let tappedTime = TimePosition(offsetDays: -4_321.25)
        let laterRailTime = TimePosition(offsetDays: 9_876.5)

        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()
        model.updateTime(normalized: tappedTime.normalized)

        let generationTask = Task { await model.generateAtStoryPreviewTime() }
        let requestedTarget = await story.waitForRequestedTarget()
        model.updateTime(normalized: laterRailTime.normalized)
        await story.releaseTargetBeat()
        await generationTask.value

        let requestedTimes = await generation.requestedTimes()
        let finalRequest = try XCTUnwrap(requestedTimes.last)
        let exactTarget = try XCTUnwrap(model.temporalStory?.targetBeat?.exactTarget)
        let generatedFrame = try XCTUnwrap(model.generatedFrame)
        let capturedTargetTime = try XCTUnwrap(model.capturedTargetTime)
        XCTAssertEqual(requestedTarget.offsetDays, tappedTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(finalRequest.offsetDays, tappedTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(generatedFrame.time.offsetDays, tappedTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(capturedTargetTime.offsetDays, tappedTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(model.selectedTime.offsetDays, tappedTime.offsetDays, accuracy: 0.001)
        XCTAssertEqual(exactTarget.offsetDays, tappedTime.offsetDays, accuracy: 0.001)
        XCTAssertNotEqual(finalRequest, laterRailTime)
        XCTAssertEqual(model.phase, .result)
    }

    func testBrowsedTimeGenerationIsSingleFlightWhileWritingExactBeat() async {
        let story = GatedTargetBeatStoryProvider()
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: story,
            generation: TimeRecordingGenerationProvider(
                outputData: makeTestJPEG(width: 900, height: 1_200)
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
        model.updateTime(normalized: 0.42)

        let first = Task { await model.generateAtStoryPreviewTime() }
        _ = await story.waitForRequestedTarget()
        XCTAssertTrue(model.isPreparingBrowsedTimeGeneration)
        await model.generateAtStoryPreviewTime()
        let targetBeatRequestCount = await story.targetBeatRequestCount()
        XCTAssertEqual(targetBeatRequestCount, 1)

        await story.releaseTargetBeat()
        await first.value
        XCTAssertFalse(model.isPreparingBrowsedTimeGeneration)
        XCTAssertEqual(model.phase, .result)
    }

    func testRetakeIgnoresLateExactBeatFailure() async {
        let story = GatedFailingTargetBeatStoryProvider()
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: story,
            generation: TimeRecordingGenerationProvider(
                outputData: makeTestJPEG(width: 900, height: 1_200)
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
        model.updateTime(normalized: -0.46)

        let request = Task { await model.generateAtStoryPreviewTime() }
        await story.waitUntilRequested()
        model.retake()
        await story.failTargetBeat()
        await request.value

        XCTAssertEqual(model.phase, .viewfinder)
        XCTAssertNil(model.failedStage)
        XCTAssertNil(model.lastErrorMessage)
        XCTAssertFalse(model.isPreparingBrowsedTimeGeneration)
    }

    func testRetryAfterExactBeatFailureKeepsBrowsedTargetTime() async throws {
        let story = FailOnceTargetBeatStoryProvider()
        let generation = TimeRecordingGenerationProvider(
            outputDataByRequest: [
                makeTestJPEG(width: 900, height: 1_200),
                makeTestJPEG(width: 1_200, height: 900),
            ]
        )
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: story,
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        let browsedTarget = TimePosition(offsetDays: 7_654.25)

        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()
        model.updateTime(normalized: browsedTarget.normalized)

        await model.generateAtStoryPreviewTime()
        XCTAssertEqual(model.phase, .pipelineFailure)
        XCTAssertEqual(model.failedStage, .story)

        await model.retryPipeline()

        let generatedFrame = try XCTUnwrap(model.generatedFrame)
        let requestedTimes = await generation.requestedTimes()
        let retriedTime = try XCTUnwrap(requestedTimes.last)
        XCTAssertEqual(requestedTimes.count, 2)
        XCTAssertEqual(
            retriedTime.offsetDays,
            browsedTarget.offsetDays,
            accuracy: 0.001
        )
        XCTAssertEqual(
            generatedFrame.time.offsetDays,
            browsedTarget.offsetDays,
            accuracy: 0.001
        )
        XCTAssertEqual(model.phase, .result)
    }

    func testBrowsedExactBeatOneHourAwayIsRejectedBeforeImageGeneration() async throws {
        let generation = TimeRecordingGenerationProvider(
            outputData: makeTestJPEG(width: 900, height: 1_200)
        )
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: OneHourMismatchedTargetBeatStoryProvider(),
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        let browsedTarget = TimePosition(offsetDays: 7_654.25)

        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        await model.capture()
        let originalFrameID = try XCTUnwrap(model.generatedFrame?.id)
        model.updateTime(normalized: browsedTarget.normalized)

        await model.generateAtStoryPreviewTime()

        XCTAssertEqual(model.phase, .pipelineFailure)
        XCTAssertEqual(model.failedStage, .story)
        XCTAssertEqual(model.generatedFrame?.id, originalFrameID)
        let requestedTimes = await generation.requestedTimes()
        XCTAssertEqual(requestedTimes.count, 1)
        XCTAssertTrue(model.lastErrorMessage?.contains("时间没有对齐") == true)
    }

    func testProviderFrameOneHourAwayIsRejected() async {
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MismatchedTimeGenerationProvider(
                outputData: makeTestJPEG(width: 900, height: 1_200)
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
        XCTAssertNil(model.generatedFrame)
        XCTAssertTrue(model.lastErrorMessage?.contains("时间没有对齐") == true)
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

    func testGenerationBeatRejectsExactTargetOneHourAway() {
        let requestedTime = TimePosition(offsetDays: 10 * 365.25)
        let canonicalBeat = StoryBeat(
            anchorYears: requestedTime.offsetYears,
            title: "标准节点",
            narrative: "标准叙事",
            visualPrompt: "标准提示"
        )
        let mismatchedExactBeat = StoryBeat(
            anchorYears: requestedTime.offsetYears,
            title: "错误精确节点",
            narrative: "错误精确叙事",
            visualPrompt: "错误精确提示",
            exactTarget: ExactTarget(
                offsetDays: requestedTime.offsetDays + 1.0 / 24.0,
                targetDateISO: "",
                compactLabel: requestedTime.compactLabel
            )
        )
        let story = TemporalStory(
            title: "时间故事",
            logline: "同一场景",
            presentTruth: "此刻",
            identityRules: [],
            beats: [canonicalBeat],
            targetBeat: mismatchedExactBeat
        )

        XCTAssertEqual(story.generationBeat(for: requestedTime)?.id, canonicalBeat.id)
    }

    func testVisibleNarrativeDoesNotRepeatDedicatedTimeLabel() {
        let time = TimePosition(offsetDays: 8.5 * 365.25)

        XCTAssertEqual(
            StoryCopyPolicy.removingRepeatedTimePrefix(
                from: "8.5 年后，植被覆盖了旧步道。",
                time: time
            ),
            "植被覆盖了旧步道。"
        )
        XCTAssertEqual(
            StoryCopyPolicy.removingRepeatedTimePrefix(
                from: "树影越过了旧围墙。",
                time: time
            ),
            "树影越过了旧围墙。"
        )
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

    func testResultLayoutAccountsForSafeAreaTopOnce() {
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

        XCTAssertEqual(
            withReportedInset.photoTop,
            withoutReportedInset.photoTop + 59,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            withReportedInset.photoSize.width,
            withoutReportedInset.photoSize.width,
            accuracy: 0.000_001
        )
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

    func testHeroSlotPreferencesRetainResultDestinationForPersistentPhoto() {
        let generating = HeroSlotPreference(
            frame: CGRect(x: 80, y: 260, width: 180, height: 240),
            cornerRadius: PosterRadius.photoPaper
        )
        let result = HeroSlotPreference(
            frame: CGRect(x: 0, y: 58, width: 390, height: 520),
            cornerRadius: PosterRadius.card
        )
        var preferences = HeroSlotPreferenceKey.defaultValue

        HeroSlotPreferenceKey.reduce(value: &preferences) {
            [.generating: generating]
        }
        HeroSlotPreferenceKey.reduce(value: &preferences) {
            [.result: result]
        }

        XCTAssertEqual(preferences[.generating], generating)
        XCTAssertEqual(preferences[.result], result)
    }

    func testSpatialTimelinesOnlyRunForNarrativeTransitions() {
        XCTAssertEqual(
            MotionTimeline.transition(from: .viewfinder, to: .shuttered),
            .capture
        )
        XCTAssertEqual(
            MotionTimeline.transition(from: .shuttered, to: .understanding),
            .capture
        )
        XCTAssertEqual(
            MotionTimeline.transition(from: .generating, to: .result),
            .timeReveal
        )
        XCTAssertEqual(
            MotionTimeline.transition(from: .share, to: .result),
            .none
        )
        XCTAssertEqual(
            MotionTimeline.transition(from: .connection, to: .cameraPermission),
            .cameraEntry
        )
    }

    func testSpatialMotionClampAndRangeMapping() {
        XCTAssertEqual(FUMIRASpatialMotion.clamp(-1), 0)
        XCTAssertEqual(FUMIRASpatialMotion.clamp(2), 1)
        XCTAssertEqual(
            FUMIRASpatialMotion.map(0.5, from: 0.25...0.75, to: 10...30),
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FUMIRASpatialMotion.map(-1, from: 0.25...0.75, to: 10...30),
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(FUMIRASpatialMotion.captureFlipDegrees(0), 0, accuracy: 0.001)
        XCTAssertEqual(FUMIRASpatialMotion.captureFlipDegrees(0.36), 180, accuracy: 0.001)
        XCTAssertEqual(FUMIRASpatialMotion.captureFlipDegrees(0.72), 360, accuracy: 0.001)
        XCTAssertEqual(FUMIRASpatialMotion.captureFlipDegrees(1), 360, accuracy: 0.001)
        XCTAssertEqual(FUMIRASpatialMotion.captureFlipDegrees(2), 360, accuracy: 0.001)
    }

    func testSpatialDepthIsOrderedAndChromeStaysStable() {
        XCTAssertLessThan(
            SpatialDepthLayer.background.parallaxPoints,
            SpatialDepthLayer.environment.parallaxPoints
        )
        XCTAssertLessThan(
            SpatialDepthLayer.environment.parallaxPoints,
            SpatialDepthLayer.hero.parallaxPoints
        )
        XCTAssertLessThanOrEqual(SpatialDepthLayer.chrome.parallaxPoints, 2)
        XCTAssertEqual(SpatialDepthLayer.chrome.rotationDegrees, 0)
    }

    func testSpatialPhotoShadowMovesOppositeYawAndLiftsAway() {
        let neutral = FUMIRASpatialMotion.photoShadowOffset(
            lift: 0,
            pitch: 0,
            yaw: 0,
            motionRoll: 0,
            motionPitch: 0
        )
        let tilted = FUMIRASpatialMotion.photoShadowOffset(
            lift: 0.8,
            pitch: 0,
            yaw: 8,
            motionRoll: 0,
            motionPitch: 0
        )

        XCTAssertLessThan(tilted.width, neutral.width)
        XCTAssertGreaterThan(tilted.height, neutral.height)
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
        XCTAssertEqual(model.temporalCapturePacket?.origin, .photoLibrary)
        XCTAssertFalse(model.temporalCapturePacket?.microTimeSlice.isAvailable ?? true)
        XCTAssertFalse(model.temporalCapturePacket?.motion.wasAnchored ?? true)
        XCTAssertTrue(model.temporalCapturePacket?.visualContext.isAvailable == true)
        XCTAssertFalse(model.temporalCapturePacket?.opticalContext.isAvailable ?? true)
        XCTAssertEqual(
            model.temporalCapturePacket?.visualContext.salientRegions.count,
            2
        )
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

    func testFutureForkRegeneratesFromOriginalAtSameExactTime() async throws {
        let output = makeTestJPEG(width: 720, height: 960)
        let generation = TimeRecordingGenerationProvider(outputData: output)
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        let target = TimePosition(offsetDays: 12 * 365.25)
        let understanding = SceneUnderstanding.parkReference
        let story = TemporalStory.fallback(
            understanding: understanding,
            targetTime: target
        )
        let source = CapturedPhoto(
            data: makeTestJPEG(width: 900, height: 1_200),
            pixelWidth: 900,
            pixelHeight: 1_200
        )
        let originalFrameID = UUID()
        model.capturedPhoto = source
        model.sceneUnderstanding = understanding
        model.temporalStory = story
        model.capturedTargetTime = target
        model.selectedTime = target
        model.generatedFrame = GeneratedFrame(
            id: originalFrameID,
            sessionID: UUID(),
            time: target,
            storyBeatID: story.targetBeat?.id,
            imageData: source.data
        )
        model.generatedPhoto = source
        model.phase = .result

        let fork = try XCTUnwrap(
            TemporalFutureForkEngine.resolve(
                understanding: understanding,
                target: target
            ).branches.dropFirst().first
        )
        await model.generateFutureFork(fork)

        XCTAssertEqual(model.phase, .result)
        XCTAssertEqual(model.generatedFrame?.time, target)
        XCTAssertEqual(model.selectedTime, target)
        XCTAssertEqual(model.capturedTargetTime, target)
        XCTAssertEqual(model.generatedFrame?.futureForkID, fork.id)
        XCTAssertEqual(model.generatedFrame?.futureForkTitle, fork.title)
        XCTAssertEqual(model.previousGeneratedFrame?.id, originalFrameID)
        let requestedTimes = await generation.requestedTimes()
        let requestedStoryBeats = await generation.requestedStoryBeats()
        XCTAssertEqual(requestedTimes, [target])

        let requestedBeat = try XCTUnwrap(requestedStoryBeats.last ?? nil)
        XCTAssertEqual(requestedBeat.id, story.targetBeat?.id)
        XCTAssertEqual(requestedBeat.exactTarget, story.targetBeat?.exactTarget)
        XCTAssertEqual(requestedBeat.renderPlan, story.targetBeat?.renderPlan)
        XCTAssertTrue(requestedBeat.visualPrompt.contains("解释分支"))
    }

    func testFutureForkWithDifferentTargetCannotStartGeneration() async throws {
        let output = makeTestJPEG(width: 720, height: 960)
        let generation = TimeRecordingGenerationProvider(outputData: output)
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        let generatedTarget = TimePosition(offsetDays: 10 * 365.25)
        let otherTarget = TimePosition(offsetDays: 20 * 365.25)
        let understanding = SceneUnderstanding.parkReference
        let story = TemporalStory.fallback(
            understanding: understanding,
            targetTime: generatedTarget
        )
        let source = CapturedPhoto(
            data: makeTestJPEG(width: 900, height: 1_200),
            pixelWidth: 900,
            pixelHeight: 1_200
        )
        let frame = GeneratedFrame(
            sessionID: UUID(),
            time: generatedTarget,
            storyBeatID: story.targetBeat?.id,
            imageData: source.data
        )
        model.capturedPhoto = source
        model.sceneUnderstanding = understanding
        model.temporalStory = story
        model.capturedTargetTime = generatedTarget
        model.selectedTime = generatedTarget
        model.generatedFrame = frame
        model.generatedPhoto = source
        model.phase = .result

        let mismatchedFork = try XCTUnwrap(
            TemporalFutureForkEngine.resolve(
                understanding: understanding,
                target: otherTarget
            ).branches.first
        )
        await model.generateFutureFork(mismatchedFork)

        XCTAssertEqual(model.phase, .result)
        XCTAssertEqual(model.generatedFrame?.id, frame.id)
        let requestedTimes = await generation.requestedTimes()
        XCTAssertTrue(requestedTimes.isEmpty)
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

private actor TimeRecordingGenerationProvider: GenerationProvider {
    private let outputDataByRequest: [Data]
    private var times: [TimePosition] = []
    private var storyBeats: [StoryBeat?] = []

    init(outputData: Data) {
        outputDataByRequest = [outputData]
    }

    init(outputDataByRequest: [Data]) {
        precondition(!outputDataByRequest.isEmpty)
        self.outputDataByRequest = outputDataByRequest
    }

    func generate(
        request: ImageGenerationRequest
    ) async -> AsyncThrowingStream<GenerationEvent, Error> {
        let outputIndex = min(times.count, outputDataByRequest.count - 1)
        let outputData = outputDataByRequest[outputIndex]
        times.append(request.time)
        storyBeats.append(request.storyBeat)
        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(GeneratedFrame(
                sessionID: request.sessionID,
                time: request.time,
                storyBeatID: request.storyBeat?.id,
                prompt: request.prompt,
                modelOptionID: request.model.id,
                imageData: outputData
            )))
            continuation.finish()
        }
    }

    func requestedTimes() -> [TimePosition] {
        times
    }

    func requestedStoryBeats() -> [StoryBeat?] {
        storyBeats
    }
}

private actor GatedTargetBeatStoryProvider: StoryProvider {
    private var requestedTarget: TimePosition?
    private var targetBeatContinuation: CheckedContinuation<Void, Never>?
    private var requestCount = 0

    func writeTargetBeat(
        understanding: SceneUnderstanding,
        story: TemporalStory,
        target: TimePosition
    ) async throws -> StoryBeat {
        requestCount += 1
        requestedTarget = target
        await withCheckedContinuation { continuation in
            targetBeatContinuation = continuation
        }
        guard let targetBeat = TemporalStory.fallback(
            understanding: understanding,
            targetTime: target
        ).targetBeat else {
            throw GenerationError.generationFailed(message: "测试目标节点生成失败。")
        }
        return targetBeat
    }

    func write(
        request: StoryRequest
    ) async -> AsyncThrowingStream<StoryEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(.fallback(
                understanding: request.understanding,
                targetTime: request.targetTime
            )))
            continuation.finish()
        }
    }

    func waitForRequestedTarget() async -> TimePosition {
        while requestedTarget == nil {
            await Task.yield()
        }
        return requestedTarget ?? .now
    }

    func releaseTargetBeat() {
        targetBeatContinuation?.resume()
        targetBeatContinuation = nil
    }

    func targetBeatRequestCount() -> Int {
        requestCount
    }
}

private actor GatedFailingTargetBeatStoryProvider: StoryProvider {
    private var wasRequested = false
    private var continuation: CheckedContinuation<Void, Never>?

    func writeTargetBeat(
        understanding: SceneUnderstanding,
        story: TemporalStory,
        target: TimePosition
    ) async throws -> StoryBeat {
        wasRequested = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw GenerationError.networkFailure
    }

    func write(
        request: StoryRequest
    ) async -> AsyncThrowingStream<StoryEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(.fallback(
                understanding: request.understanding,
                targetTime: request.targetTime
            )))
            continuation.finish()
        }
    }

    func waitUntilRequested() async {
        while !wasRequested {
            await Task.yield()
        }
    }

    func failTargetBeat() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FailOnceTargetBeatStoryProvider: StoryProvider {
    private var requestCount = 0

    func writeTargetBeat(
        understanding: SceneUnderstanding,
        story: TemporalStory,
        target: TimePosition
    ) async throws -> StoryBeat {
        requestCount += 1
        if requestCount == 1 {
            throw GenerationError.networkFailure
        }
        guard let targetBeat = TemporalStory.fallback(
            understanding: understanding,
            targetTime: target
        ).targetBeat else {
            throw GenerationError.generationFailed(message: "测试目标节点生成失败。")
        }
        return targetBeat
    }

    func write(
        request: StoryRequest
    ) async -> AsyncThrowingStream<StoryEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(.fallback(
                understanding: request.understanding,
                targetTime: request.targetTime
            )))
            continuation.finish()
        }
    }
}

private actor MismatchedTimeGenerationProvider: GenerationProvider {
    let outputData: Data

    init(outputData: Data) {
        self.outputData = outputData
    }

    func generate(
        request: ImageGenerationRequest
    ) async -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(GeneratedFrame(
                sessionID: request.sessionID,
                time: TimePosition(offsetDays: request.time.offsetDays + 1.0 / 24.0),
                storyBeatID: request.storyBeat?.id,
                prompt: request.prompt,
                modelOptionID: request.model.id,
                imageData: outputData
            )))
            continuation.finish()
        }
    }
}

private actor OneHourMismatchedTargetBeatStoryProvider: StoryProvider {
    func writeTargetBeat(
        understanding: SceneUnderstanding,
        story: TemporalStory,
        target: TimePosition
    ) async throws -> StoryBeat {
        let mismatchedTarget = TimePosition(
            offsetDays: target.offsetDays + 1.0 / 24.0
        )
        guard let beat = TemporalStory.fallback(
            understanding: understanding,
            targetTime: mismatchedTarget
        ).targetBeat else {
            throw GenerationError.generationFailed(message: "测试目标节点生成失败。")
        }
        return beat
    }

    func write(
        request: StoryRequest
    ) async -> AsyncThrowingStream<StoryEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(.fallback(
                understanding: request.understanding,
                targetTime: request.targetTime
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

    func writeTargetBeat(
        understanding: SceneUnderstanding,
        story: TemporalStory,
        target: TimePosition
    ) async throws -> StoryBeat {
        guard let beat = TemporalStory.fallback(
            understanding: understanding,
            targetTime: target
        ).targetBeat else {
            throw GenerationError.generationFailed(message: "测试目标节点生成失败。")
        }
        return beat
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

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

    func testCaptureMustUnderstandAndWriteStoryBeforeGeneration() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()

        await model.capture()

        XCTAssertEqual(model.phase, .storyReady)
        XCTAssertNotNil(model.capturedPhoto)
        XCTAssertNotNil(model.capturedPhoto.flatMap { UIImage(data: $0.data) })
        XCTAssertNotNil(model.sceneUnderstanding)
        XCTAssertNotNil(model.temporalStory)
        XCTAssertNil(model.generatedFrame)
        XCTAssertEqual(model.understandingProgress, 1)
        XCTAssertEqual(model.storyProgress, 1)
    }

    func testConfirmedStoryGeneratesIdentityAwareFrame() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        model.updateTime(normalized: 0.8)
        await model.capture()

        await model.generateStoryWorld()

        XCTAssertEqual(model.phase, .result)
        XCTAssertEqual(model.generatedFrame?.sessionID, model.activeSessionID)
        XCTAssertEqual(model.generatedFrame?.modelOptionID, "demo.image.identity")
        XCTAssertTrue(model.generatedFrame?.prompt.contains("主体连续性") == true)
        XCTAssertTrue(model.generatedFrame?.prompt.contains("保持原图构图") == true)
    }

    func testStoryNarrativeChangesAcrossTime() {
        let story = TemporalStory.demoPark
        let past = story.narrative(for: TimePosition(offsetDays: -36_525))
        let present = story.narrative(for: .now)
        let future = story.narrative(for: TimePosition(offsetDays: 36_525))

        XCTAssertNotEqual(past, present)
        XCTAssertNotEqual(present, future)
        XCTAssertNotEqual(past, future)
    }

    func testOnlyReadyModelRoutesCanRun() {
        let catalog = AIModelCatalog.bundled
        XCTAssertTrue(catalog.isRunnable(.demo))

        var unavailable = AIModelConfiguration.demo
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

    func testCancelGenerationReturnsToStoryReadyWithoutFailure() async {
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
        XCTAssertEqual(model.phase, .storyReady)

        let generateTask = Task { await model.generateStoryWorld() }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.phase, .generating)
        model.cancelGeneration()

        await generateTask.value
        XCTAssertEqual(model.phase, .storyReady)
        XCTAssertNil(model.activeSessionID)
        XCTAssertNil(model.failedStage)
        XCTAssertNil(model.generatedFrame)
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

        await model.generateStoryWorld()
        XCTAssertEqual(model.phase, .pipelineFailure)
        XCTAssertEqual(model.failedStage, .imageGeneration)
        XCTAssertEqual(model.lastGenerationError, .timedOut)
        XCTAssertTrue(model.canRetryFailedStage)

        await model.retryPipeline()
        XCTAssertEqual(model.phase, .result)
        XCTAssertNotNil(model.generatedFrame)
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
        await model.capture()

        let first = Task { await model.generateStoryWorld() }
        try? await Task.sleep(for: .milliseconds(40))
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
        await model.generateStoryWorld()

        XCTAssertEqual(model.lastGenerationError, .invalidParameters)
        XCTAssertFalse(model.canRetryFailedStage)

        await model.retryPipeline()
        XCTAssertEqual(model.phase, .storyReady)
        XCTAssertNil(model.failedStage)
    }

    func testImportPhotoEntersSamePipelineAsCapture() async throws {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()

        let landscape = makeTestJPEG(width: 1_200, height: 800)
        await model.importPhoto(imageData: landscape)

        XCTAssertEqual(model.phase, .storyReady)
        XCTAssertNotNil(model.capturedPhoto)
        XCTAssertNotNil(model.sceneUnderstanding)
        XCTAssertNotNil(model.temporalStory)
        let photo = try XCTUnwrap(model.capturedPhoto)
        let ratio = Double(photo.pixelWidth) / Double(photo.pixelHeight)
        XCTAssertEqual(ratio, 0.75, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
    }

    func testRegenerateResultReplacesFrameAndSupportsOneUndo() async {
        let model = AppModel(dependencies: .test)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()
        model.updateTime(normalized: 0.7)
        await model.capture()
        await model.generateStoryWorld()

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

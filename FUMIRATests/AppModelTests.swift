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
        #endif
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
        XCTAssertNil(model.activeSessionID)
        XCTAssertEqual(model.temporalStory?.id, storyID)
    }
}

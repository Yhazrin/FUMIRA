import Foundation
import XCTest
@testable import FUMIRA

@MainActor
final class CameraLiveActivityTests: XCTestCase {
    func testContentStateRoundTripsThroughActivityKitPayloadEncoding() throws {
        let state = CameraLiveActivityAttributes.ContentState(
            phase: .understanding,
            targetLabel: "8.5年后",
            zoomLabel: "1.0×",
            flashSymbol: "bolt.badge.automatic.fill",
            lensSymbol: "arrow.triangle.2.circlepath",
            isGridEnabled: true,
            aspectRatioLabel: "3:4",
            progress: 0.42
        )

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            CameraLiveActivityAttributes.ContentState.self,
            from: encoded
        )

        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.isProcessing)
        XCTAssertFalse(decoded.isCameraPhase)
        XCTAssertEqual(decoded.normalizedProgress, 0.42, accuracy: 0.001)
    }

    func testProgressClampsAndTerminalPhasesDoNotRenderAsProcessing() {
        var state = CameraLiveActivityAttributes.ContentState(
            phase: .generating,
            targetLabel: "8.5年后",
            zoomLabel: "1.0×",
            flashSymbol: "bolt.fill",
            lensSymbol: "camera.rotate.fill",
            isGridEnabled: false,
            aspectRatioLabel: "3:4",
            progress: 1.4
        )

        XCTAssertEqual(state.normalizedProgress, 1, accuracy: 0.001)
        XCTAssertTrue(state.isProcessing)

        state.progress = -0.2
        XCTAssertEqual(state.normalizedProgress, 0, accuracy: 0.001)

        state.phase = .ready
        XCTAssertFalse(state.isProcessing)
        XCTAssertFalse(state.isCameraPhase)
    }

    func testCapturePipelineCarriesLiveActivityThroughReady() async {
        let recorder = RecordingCameraLiveActivityService()
        let base = AppDependencies.test
        let dependencies = AppDependencies(
            camera: base.camera,
            cameraPreview: base.cameraPreview,
            hardware: base.hardware,
            understanding: base.understanding,
            story: base.story,
            generation: base.generation,
            modelCatalog: base.modelCatalog,
            modelConfigurationStore: base.modelConfigurationStore,
            storage: base.storage,
            haptics: base.haptics,
            motionField: base.motionField,
            captureMotion: base.captureMotion,
            sceneLayerAnalyzer: base.sceneLayerAnalyzer,
            cameraActivity: recorder
        )
        let model = AppModel(dependencies: dependencies)
        await model.prepare()
        model.beginPhoneOnlyPath()
        await model.grantCameraAccess()

        await model.capture()

        let snapshot = await recorder.snapshot()
        XCTAssertTrue(snapshot.updates.contains { $0.phase == .captured })
        XCTAssertTrue(snapshot.updates.contains { $0.phase == .understanding })
        XCTAssertTrue(snapshot.updates.contains { $0.phase == .storyWriting })
        XCTAssertTrue(snapshot.updates.contains { $0.phase == .generating })
        XCTAssertEqual(snapshot.finished.last?.phase, .ready)
        XCTAssertEqual(snapshot.finished.last?.normalizedProgress, 1)
    }

    func testDynamicIslandCameraLinksReachViewfinderActions() {
        let model = AppModel(dependencies: .test)
        model.phase = .viewfinder

        model.handleDeepLink(URL(string: "fumira://camera/grid")!)
        XCTAssertTrue(model.isCameraGridEnabled)

        XCTAssertEqual(model.cameraAspectRatio, .classic)
        model.handleDeepLink(URL(string: "fumira://camera/aspect")!)
        XCTAssertEqual(model.cameraAspectRatio, .square)
    }
}

private actor RecordingCameraLiveActivityService: CameraLiveActivityService {
    struct Snapshot: Sendable {
        let updates: [CameraLiveActivityAttributes.ContentState]
        let finished: [CameraLiveActivityAttributes.ContentState]
    }

    private var updates: [CameraLiveActivityAttributes.ContentState] = []
    private var finished: [CameraLiveActivityAttributes.ContentState] = []

    func trigger(with state: CameraLiveActivityAttributes.ContentState) async throws {
        updates.append(state)
    }

    func update(with state: CameraLiveActivityAttributes.ContentState) async {
        updates.append(state)
    }

    func finish(with state: CameraLiveActivityAttributes.ContentState) async {
        finished.append(state)
    }

    func dismissAll() async {}

    func snapshot() -> Snapshot {
        Snapshot(updates: updates, finished: finished)
    }
}

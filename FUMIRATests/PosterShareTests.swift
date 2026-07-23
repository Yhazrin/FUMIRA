import XCTest
import UIKit
@testable import FUMIRA

@MainActor
final class PosterShareTests: XCTestCase {
    func testComposerRendersNonEmptyPNG() throws {
        let data = try PosterComposer.renderPNG(
            time: TimePosition(normalized: 0.4),
            yearLabel: PosterComposer.yearLabel(for: TimePosition(normalized: 0.4)),
            title: "公园会记得你",
            narrative: "同一条小路，树影更长了一些。",
            sceneImageData: nil
        )
        XCTAssertFalse(data.isEmpty)
        XCTAssertNotNil(UIImage(data: data))
    }

    func testYearLabelNearNowIsNOW() {
        XCTAssertEqual(PosterComposer.yearLabel(for: .now), "NOW")
        // Nonlinear map: |normalized| ≲ 0.1 still lands inside the ±0.5y NOW band.
        XCTAssertEqual(PosterComposer.yearLabel(for: TimePosition(normalized: 0.01)), "NOW")
        XCTAssertTrue(PosterComposer.yearLabel(for: TimePosition(normalized: 0.2)).contains("年"))
    }

    func testMockStoragePersistsPNGAndReturnsFileURL() async throws {
        let storage = MockPosterStorage()
        let png = try PosterComposer.renderPNG(
            time: .now,
            yearLabel: "NOW",
            title: "此刻",
            narrative: "测试叙事",
            sceneImageData: nil
        )
        let snapshot = PosterSnapshot(
            time: .now,
            title: "此刻",
            yearLabel: "NOW",
            imageData: png
        )
        let url = try await storage.save(snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let saved = await storage.savedSnapshots
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.title, "此刻")
    }

    func testMockStorageFailureSurfacesError() async {
        let storage = MockPosterStorage()
        await storage.reset()
        await storage.setShouldFail(true)
        do {
            _ = try await storage.save(
                PosterSnapshot(time: .now, title: "x", yearLabel: "NOW", imageData: Data([0x89, 0x50]))
            )
            XCTFail("Expected failure")
        } catch let error as PosterStorageError {
            XCTAssertEqual(error.localizedDescription.contains("mock"), true)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testSavePosterThroughAppModelUsesStorage() async throws {
        let storage = MockPosterStorage()
        let dependencies = AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MockGenerationProvider(stepDelay: .zero),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: storage,
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService()
        )
        let model = AppModel(dependencies: dependencies)
        model.temporalStory = .demoPark
        model.generatedFrame = GeneratedFrame(
            sessionID: UUID(),
            time: .now,
            prompt: "test"
        )
        model.openShare()
        await model.prepareSharePoster()
        XCTAssertNotNil(model.shareImageData)

        await model.savePosterToLibrary()
        XCTAssertNotNil(model.posterURL)
        XCTAssertEqual(model.shareFeedbackMessage, "已保存到相册")
        XCTAssertNil(model.lastErrorMessage)
        let saved = await storage.savedSnapshots
        XCTAssertEqual(saved.count, 1)
    }

    func testOpenShareThenReturnPreservesTime() {
        let model = AppModel(dependencies: .test)
        model.temporalStory = .demoPark
        model.selectedTime = TimePosition(normalized: 0.55)
        model.openShare()
        XCTAssertEqual(model.phase, .share)
        model.returnToResult()
        XCTAssertEqual(model.phase, .result)
        XCTAssertEqual(model.selectedTime.normalized, 0.55, accuracy: 0.000_001)
    }

    func testDeepLinkShareOpensShareWhenStoryReady() {
        let model = AppModel(dependencies: .test)
        model.temporalStory = .demoPark
        model.handleDeepLink(URL(string: "fumira://share")!)
        XCTAssertEqual(model.phase, .share)
    }

    func testDeepLinkIgnoredWithoutStory() {
        let model = AppModel(dependencies: .test)
        model.handleDeepLink(URL(string: "fumira://share")!)
        XCTAssertEqual(model.phase, .connection)
    }
}

extension MockPosterStorage {
    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
}

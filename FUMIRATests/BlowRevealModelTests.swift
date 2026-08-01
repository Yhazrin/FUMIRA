import XCTest
@testable import FUMIRA

@MainActor
final class BlowRevealModelTests: XCTestCase {
    func testLiveSamplesDriveOneObservableSnapshot() async {
        let service = MockBlowInputService()
        let model = BlowRevealModel(service: service)
        let start = ProcessInfo.processInfo.systemUptime

        model.activate()
        await Task.yield()

        for index in 1...8 {
            service.emit(
                decibels: -8,
                at: start + Double(index) * 0.1
            )
            await Task.yield()
        }

        XCTAssertTrue(model.isActive)
        XCTAssertEqual(model.availability, .liveMicrophone)
        XCTAssertGreaterThan(model.snapshot.gust, 0)
        XCTAssertGreaterThan(model.snapshot.revealProgress, 0)
        model.deactivate()
    }

    func testPermissionFallbackStopsMonitoringAndRecommendsButton() async {
        let service = MockBlowInputService(
            availability: .fallbackRequired(.microphonePermissionDenied)
        )
        let model = BlowRevealModel(service: service)

        model.activate()
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(model.isActive)
        XCTAssertTrue(model.fallbackRecommended)
        XCTAssertEqual(
            model.availability,
            .fallbackRequired(.microphonePermissionDenied)
        )
    }

    func testResetClearsPartialReveal() async {
        let service = MockBlowInputService()
        let model = BlowRevealModel(service: service)
        let start = ProcessInfo.processInfo.systemUptime

        model.activate()
        await Task.yield()
        service.emit(decibels: -8, at: start + 0.2)
        await Task.yield()
        XCTAssertGreaterThan(model.snapshot.revealProgress, 0)

        model.reset()

        XCTAssertEqual(model.snapshot.gust, 0)
        XCTAssertEqual(model.snapshot.revealProgress, 0)
        XCTAssertEqual(model.availability, .unknown)
    }
}

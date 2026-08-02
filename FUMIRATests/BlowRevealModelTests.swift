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
        let settled = await waitUntil(timeout: 0.5) {
            model.fallbackRecommended && !model.isActive
        }

        XCTAssertTrue(settled)
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
        for index in 1...8 {
            service.emit(decibels: -8, at: start + Double(index) * 0.1)
            await Task.yield()
        }
        let advanced = await waitUntil(timeout: 0.5) {
            model.snapshot.revealProgress > 0
        }
        XCTAssertTrue(advanced)
        XCTAssertGreaterThan(model.snapshot.revealProgress, 0)

        model.reset()

        XCTAssertEqual(model.snapshot.gust, 0)
        XCTAssertEqual(model.snapshot.revealProgress, 0)
        XCTAssertEqual(model.availability, .unknown)
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

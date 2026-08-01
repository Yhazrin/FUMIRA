import XCTest
@testable import FUMIRA

@MainActor
final class CaptureMotionModelTests: XCTestCase {
    func testNaturalStreamEndMarksMotionInactive() async {
        let model = CaptureMotionModel(
            service: FiniteCaptureMotionService(),
            haptics: MockHapticsClient()
        )

        model.activate()
        XCTAssertTrue(model.isActive)

        for _ in 0..<50 where model.isActive {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(model.isActive)
    }
}

private struct FiniteCaptureMotionService: CaptureMotionProviding {
    func samples() -> AsyncStream<CaptureMotionSample> {
        AsyncStream { continuation in
            continuation.yield(
                CaptureMotionSample(
                    timestamp: 1,
                    roll: 0.2,
                    pitch: 0,
                    yaw: 0,
                    rotationRate: 0,
                    acceleration: 0,
                    stability: 1
                )
            )
            continuation.finish()
        }
    }

    func start() async {}
    func stop() async {}
}

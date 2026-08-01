import XCTest
@testable import FUMIRA

@MainActor
final class TemporalShakeModelTests: XCTestCase {
    func testDeviceShakePublishesOnlyAdvanceBranchEvent() async {
        let clock = TemporalShakeTestClock(now: 1)
        let service = MockTemporalShakeService()
        let model = TemporalShakeModel(
            service: service,
            policy: policy,
            clock: { clock.now }
        )

        model.activate(reduceMotion: false)
        await waitUntil { model.isMonitoring }
        service.emitSystemShake(at: 1)
        await waitUntil { model.latestEvent != nil }

        XCTAssertEqual(model.availability, .motionShakeResponder)
        XCTAssertEqual(
            model.latestEvent,
            .advanceBranch(source: .deviceResponder, timestamp: 1)
        )
        model.deactivate()
    }

    func testReduceMotionSkipsHardwareAndKeepsButtonFallback() {
        let clock = TemporalShakeTestClock(now: 2)
        let service = MockTemporalShakeService()
        let model = TemporalShakeModel(service: service, policy: policy, clock: { clock.now })

        model.activate(reduceMotion: true)
        model.requestFallbackAdvance()

        XCTAssertEqual(service.startCallCount, 0)
        XCTAssertFalse(model.isMonitoring)
        XCTAssertTrue(model.fallbackRecommended)
        XCTAssertEqual(
            model.latestEvent,
            .advanceBranch(source: .fallbackButton, timestamp: 2)
        )
    }

    func testUnavailableResponderEndsMonitoringAndRecommendsFallback() async {
        let service = MockTemporalShakeService(availability: .fallbackRequired)
        let model = TemporalShakeModel(service: service, policy: policy)

        model.activate(reduceMotion: false)
        await waitUntil { model.availability == .fallbackRequired }
        await waitUntil { !model.isMonitoring }

        XCTAssertTrue(model.fallbackRecommended)
        XCTAssertEqual(service.startCallCount, 1)
    }

    func testBackgroundStopsAndForegroundRestartsShortLivedMonitoring() async {
        let service = MockTemporalShakeService()
        let model = TemporalShakeModel(service: service, policy: policy)

        model.activate(reduceMotion: false)
        await waitUntil { service.startCallCount == 1 }
        model.setSceneActive(false)

        XCTAssertFalse(model.isMonitoring)
        XCTAssertEqual(service.stopCallCount, 1)

        model.setSceneActive(true)
        await waitUntil { service.startCallCount == 2 }
        XCTAssertTrue(model.isMonitoring)
        model.deactivate()
    }

    func testListeningWindowStopsServiceButFallbackRemainsAvailable() async {
        let clock = TemporalShakeTestClock(now: 8)
        let service = MockTemporalShakeService()
        let shortPolicy = TemporalShakeDetectionPolicy(
            triggerThreshold: 0.8,
            releaseThreshold: 0.3,
            debounceInterval: 1,
            listeningWindow: .milliseconds(250)
        )
        let model = TemporalShakeModel(
            service: service,
            policy: shortPolicy,
            clock: { clock.now }
        )

        model.activate(reduceMotion: false)
        await waitUntil { model.isMonitoring }
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(model.isMonitoring)
        XCTAssertEqual(service.stopCallCount, 1)
        XCTAssertTrue(model.fallbackRecommended)

        model.requestFallbackAdvance()
        XCTAssertEqual(
            model.latestEvent,
            .advanceBranch(source: .fallbackButton, timestamp: 8)
        )
    }

    private var policy: TemporalShakeDetectionPolicy {
        TemporalShakeDetectionPolicy(
            triggerThreshold: 0.8,
            releaseThreshold: 0.3,
            debounceInterval: 1,
            listeningWindow: .seconds(2)
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        attempts: Int = 60
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for temporal shake state")
    }
}

private final class TemporalShakeTestClock: @unchecked Sendable {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

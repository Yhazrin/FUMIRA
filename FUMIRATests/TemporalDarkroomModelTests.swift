import XCTest
import Observation
@testable import FUMIRA

@MainActor
final class TemporalDarkroomModelTests: XCTestCase {
    func testTickerDoesNotPublishAnUnchangedFarZeroSnapshot() async {
        let clock = TemporalDarkroomTestClock(now: 0)
        let service = MockTemporalDarkroomService(
            availability: .alternativeInputRequired,
            clock: { clock.now }
        )
        let model = TemporalDarkroomModel(
            service: service,
            policy: TemporalDarkroomPolicy(
                requiredExposureDuration: 2,
                departureHoldDuration: 1,
                decayPerSecond: 0.25,
                normalTickInterval: 0.01
            ),
            clock: { clock.now }
        )

        model.activate(reduceMotion: false)
        await waitUntil {
            model.availability == .alternativeInputRequired
                && model.lastInputSource == .alternative
        }

        let snapshotChanged = expectation(
            description: "unchanged snapshot was not published"
        )
        snapshotChanged.isInverted = true
        withObservationTracking {
            _ = model.snapshot
        } onChange: {
            snapshotChanged.fulfill()
        }

        await fulfillment(of: [snapshotChanged], timeout: 0.08)

        XCTAssertEqual(model.snapshot.progress, 0, accuracy: 0.000_001)
        XCTAssertEqual(model.snapshot.inputState, .far)
        XCTAssertTrue(model.snapshot.isProcessingActive)

        model.deactivate()
    }

    func testAlternativeInputDrivesSameExposureEngineWhenSensorUnavailable() async {
        let clock = TemporalDarkroomTestClock(now: 0)
        let service = MockTemporalDarkroomService(
            availability: .alternativeInputRequired,
            clock: { clock.now }
        )
        let model = TemporalDarkroomModel(
            service: service,
            policy: TemporalDarkroomPolicy(
                requiredExposureDuration: 2,
                departureHoldDuration: 1,
                decayPerSecond: 0.25
            ),
            clock: { clock.now }
        )

        model.activate(reduceMotion: true)
        await waitUntil { model.availability == .alternativeInputRequired }

        model.setAlternativeInputActive(true)
        await waitUntil { model.snapshot.inputState == .near }
        clock.now = 1
        model.setAlternativeInputActive(false)
        await waitUntil { model.snapshot.inputState == .far }

        XCTAssertTrue(model.alternativeInputRecommended)
        XCTAssertEqual(model.lastInputSource, .alternative)
        XCTAssertEqual(model.snapshot.progress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(model.snapshot.phase, .holding)
        XCTAssertFalse(model.snapshot.shouldAnimateProgress)

        model.deactivate()
    }

    func testSceneSuspensionStopsServiceAndDoesNotAccumulateHiddenTime() async {
        let clock = TemporalDarkroomTestClock(now: 0)
        let service = MockTemporalDarkroomService(
            availability: .alternativeInputRequired,
            clock: { clock.now }
        )
        let model = TemporalDarkroomModel(
            service: service,
            policy: TemporalDarkroomPolicy(
                requiredExposureDuration: 2,
                departureHoldDuration: 1,
                decayPerSecond: 0.25
            ),
            clock: { clock.now }
        )

        model.activate(reduceMotion: true)
        await waitUntil { model.isMonitoring }
        model.setAlternativeInputActive(true)
        await waitUntil { model.snapshot.inputState == .near }

        clock.now = 1
        model.setSceneActive(false)
        let progressBeforeBackground = model.snapshot.progress
        XCTAssertFalse(model.isMonitoring)
        XCTAssertEqual(service.stopCallCount, 1)

        clock.now = 100
        model.setSceneActive(true)
        await waitUntil { service.startCallCount == 2 }

        XCTAssertEqual(
            model.snapshot.progress,
            progressBeforeBackground,
            accuracy: 0.000_001
        )

        model.deactivate()
    }

    func testCancelStopsMonitoringAndIgnoresFurtherFallbackInput() async {
        let clock = TemporalDarkroomTestClock(now: 0)
        let service = MockTemporalDarkroomService(clock: { clock.now })
        let model = TemporalDarkroomModel(
            service: service,
            clock: { clock.now }
        )

        model.activate(reduceMotion: false)
        await waitUntil { model.isMonitoring }
        model.setAlternativeInputActive(true)
        await waitUntil { model.snapshot.inputState == .near }
        model.cancel()

        clock.now = 10
        model.setAlternativeInputActive(true)

        XCTAssertEqual(model.snapshot.phase, .cancelled)
        XCTAssertFalse(model.isActive)
        XCTAssertFalse(model.isMonitoring)
        XCTAssertEqual(service.stopCallCount, 1)
    }

    func testDeactivatePreservesProgressAndResetStartsClean() async {
        let clock = TemporalDarkroomTestClock(now: 0)
        let service = MockTemporalDarkroomService(clock: { clock.now })
        let model = TemporalDarkroomModel(
            service: service,
            policy: TemporalDarkroomPolicy(
                requiredExposureDuration: 2,
                departureHoldDuration: 1,
                decayPerSecond: 0.25
            ),
            clock: { clock.now }
        )

        model.activate(reduceMotion: false)
        await waitUntil { model.isMonitoring }
        model.setAlternativeInputActive(true)
        await waitUntil { model.snapshot.inputState == .near }
        clock.now = 1
        model.setAlternativeInputActive(false)
        await waitUntil { model.snapshot.inputState == .far }
        let developedProgress = model.snapshot.progress

        model.deactivate()

        XCTAssertEqual(
            model.snapshot.progress,
            developedProgress,
            accuracy: 0.000_001
        )
        XCTAssertEqual(model.snapshot.phase, .suspended)

        model.reset()
        XCTAssertEqual(model.snapshot.progress, 0, accuracy: 0.000_001)
        XCTAssertEqual(model.snapshot.phase, .idle)
        XCTAssertNil(model.lastInputSource)
    }

    func testNewMonitoringGenerationIgnoresOldStreamEvents() async {
        let clock = TemporalDarkroomTestClock(now: 0)
        let service = RetainingTemporalDarkroomService()
        let model = TemporalDarkroomModel(
            service: service,
            policy: TemporalDarkroomPolicy(
                requiredExposureDuration: 2,
                departureHoldDuration: 1,
                decayPerSecond: 0.25
            ),
            clock: { clock.now }
        )

        model.activate(reduceMotion: false)
        await waitUntil { service.streamCount == 1 }
        model.deactivate()
        model.activate(reduceMotion: false)
        await waitUntil { service.streamCount == 2 }

        clock.now = 1
        service.emit(.near, timestamp: 1, onStream: 0)
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(model.snapshot.inputState, .far)
        XCTAssertEqual(model.snapshot.progress, 0, accuracy: 0.000_001)

        service.emit(.near, timestamp: 1, onStream: 1)
        await waitUntil { model.snapshot.inputState == .near }
        XCTAssertEqual(model.lastInputSource, .proximitySensor)

        model.deactivate()
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        attempts: Int = 50
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for temporal darkroom state")
    }
}

private final class TemporalDarkroomTestClock: @unchecked Sendable {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

@MainActor
private final class RetainingTemporalDarkroomService: TemporalDarkroomProviding {
    private var continuations: [AsyncStream<TemporalDarkroomEvent>.Continuation] = []

    var streamCount: Int {
        continuations.count
    }

    func events() -> AsyncStream<TemporalDarkroomEvent> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }

    func start() {}
    func stop() {}

    func setAlternativeInputActive(_ isActive: Bool, timestamp: TimeInterval) {
        guard let streamIndex = continuations.indices.last else { return }
        emit(
            isActive ? .near : .far,
            timestamp: timestamp,
            onStream: streamIndex,
            source: .alternative
        )
    }

    func emit(
        _ state: TemporalDarkroomInputState,
        timestamp: TimeInterval,
        onStream streamIndex: Int,
        source: TemporalDarkroomInputSource = .proximitySensor
    ) {
        guard continuations.indices.contains(streamIndex) else { return }
        continuations[streamIndex].yield(
            .observation(
                TemporalDarkroomObservation(
                    state: state,
                    source: source,
                    timestamp: timestamp
                )
            )
        )
    }
}

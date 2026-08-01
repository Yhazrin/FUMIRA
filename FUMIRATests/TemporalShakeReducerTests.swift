import XCTest
@testable import FUMIRA

final class TemporalShakeReducerTests: XCTestCase {
    private let policy = TemporalShakeDetectionPolicy(
        triggerThreshold: 0.8,
        releaseThreshold: 0.3,
        debounceInterval: 1
    )

    func testThresholdCrossingTriggersOnlyOnceUntilRelease() {
        var reducer = TemporalShakeReducer(policy: policy)

        XCTAssertNil(reducer.reduce(.sample(sample(0.79, at: 0))))
        XCTAssertEqual(
            reducer.reduce(.sample(sample(0.8, at: 0.1))),
            TemporalShakeDetection(source: .externalSample, timestamp: 0.1)
        )
        XCTAssertNil(reducer.reduce(.sample(sample(1.4, at: 0.2))))
        XCTAssertFalse(reducer.isArmed)

        XCTAssertNil(reducer.reduce(.sample(sample(0.2, at: 0.3))))
        XCTAssertTrue(reducer.isArmed)
        XCTAssertNil(reducer.reduce(.sample(sample(1.0, at: 0.4))))

        XCTAssertNil(reducer.reduce(.sample(sample(0.1, at: 1.0))))
        XCTAssertEqual(
            reducer.reduce(.sample(sample(1.0, at: 1.2))),
            TemporalShakeDetection(source: .externalSample, timestamp: 1.2)
        )
    }

    func testDiscreteSystemEventsShareDebounceWithoutRearmRequirement() {
        var reducer = TemporalShakeReducer(policy: policy)

        XCTAssertEqual(
            reducer.reduce(.systemShakeEnded(timestamp: 2)),
            TemporalShakeDetection(source: .deviceResponder, timestamp: 2)
        )
        XCTAssertNil(reducer.reduce(.systemShakeEnded(timestamp: 2.4)))
        XCTAssertEqual(
            reducer.reduce(.systemShakeEnded(timestamp: 3)),
            TemporalShakeDetection(source: .deviceResponder, timestamp: 3)
        )
    }

    func testFallbackUsesSameDebounceClock() {
        var reducer = TemporalShakeReducer(policy: policy)

        XCTAssertEqual(
            reducer.reduce(.fallbackRequested(timestamp: 4)),
            TemporalShakeDetection(source: .fallbackButton, timestamp: 4)
        )
        XCTAssertNil(reducer.reduce(.systemShakeEnded(timestamp: 4.5)))
        XCTAssertEqual(
            reducer.reduce(.fallbackRequested(timestamp: 5)),
            TemporalShakeDetection(source: .fallbackButton, timestamp: 5)
        )
    }

    func testNonfiniteAndOutOfOrderInputsAreIgnored() {
        var reducer = TemporalShakeReducer(policy: policy)

        XCTAssertNil(reducer.reduce(.sample(sample(.nan, at: 100))))
        XCTAssertNil(reducer.reduce(.systemShakeEnded(timestamp: .infinity)))
        XCTAssertEqual(
            reducer.reduce(.systemShakeEnded(timestamp: 3)),
            TemporalShakeDetection(source: .deviceResponder, timestamp: 3)
        )
        XCTAssertNil(reducer.reduce(.fallbackRequested(timestamp: 2)))
    }

    func testPolicySanitizesUnsafeValuesAndListeningWindow() {
        let policy = TemporalShakeDetectionPolicy(
            triggerThreshold: .nan,
            releaseThreshold: 4,
            debounceInterval: -.infinity,
            listeningWindow: .milliseconds(1)
        )

        XCTAssertEqual(policy.triggerThreshold, 0.82)
        XCTAssertEqual(policy.releaseThreshold, 0.82)
        XCTAssertEqual(policy.debounceInterval, 1.2)
        XCTAssertEqual(policy.listeningWindow, .milliseconds(250))
    }

    func testReducerAndOutputsAreSendable() {
        assertSendable(TemporalShakeReducer(policy: policy))
        assertSendable(TemporalShakeDetection(source: .deviceResponder, timestamp: 1))
    }

    private func sample(_ intensity: Double, at timestamp: TimeInterval) -> TemporalShakeSample {
        TemporalShakeSample(intensity: intensity, timestamp: timestamp)
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

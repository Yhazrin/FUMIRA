import XCTest
@testable import FUMIRA

final class TemporalDarkroomEngineTests: XCTestCase {
    private let policy = TemporalDarkroomPolicy(
        requiredExposureDuration: 2,
        departureHoldDuration: 1,
        decayPerSecond: 0.25
    )

    func testNearAccumulatesThenFarHoldsAndDecays() {
        var engine = TemporalDarkroomEngine(policy: policy)
        engine.reset(at: 0)
        engine.setProcessingActive(true, at: 0)
        engine.ingest(.near, at: 0)

        engine.advance(to: 1)
        XCTAssertEqual(engine.snapshot.progress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.phase, .developing)

        engine.ingest(.far, at: 1)
        engine.advance(to: 1.75)
        XCTAssertEqual(engine.snapshot.progress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.phase, .holding)

        engine.advance(to: 2.5)
        XCTAssertEqual(engine.snapshot.progress, 0.375, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.phase, .receding)
    }

    func testCompletedExposureIsSticky() {
        var engine = TemporalDarkroomEngine(policy: policy)
        engine.reset(at: 0)
        engine.setProcessingActive(true, at: 0)
        engine.ingest(.near, at: 0)
        engine.advance(to: 2)

        XCTAssertEqual(engine.snapshot.phase, .developed)
        XCTAssertEqual(engine.snapshot.progress, 1, accuracy: 0.000_001)

        engine.ingest(.far, at: 2)
        engine.advance(to: 200)

        XCTAssertEqual(engine.snapshot.phase, .developed)
        XCTAssertEqual(engine.snapshot.progress, 1, accuracy: 0.000_001)
    }

    func testSuspensionDoesNotCountBackgroundTime() {
        var engine = TemporalDarkroomEngine(policy: policy)
        engine.reset(at: 0)
        engine.setProcessingActive(true, at: 0)
        engine.ingest(.near, at: 0)
        engine.advance(to: 1)

        engine.setProcessingActive(false, at: 1)
        engine.advance(to: 100)
        XCTAssertEqual(engine.snapshot.progress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.phase, .suspended)

        engine.setProcessingActive(true, at: 100)
        engine.advance(to: 101)
        XCTAssertEqual(engine.snapshot.progress, 1, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.phase, .developed)
    }

    func testCancellationIsTerminalUntilReset() {
        var engine = TemporalDarkroomEngine(policy: policy)
        engine.reset(at: 0)
        engine.setProcessingActive(true, at: 0)
        engine.ingest(.near, at: 0)
        engine.advance(to: 0.5)
        engine.cancel(at: 0.5)

        engine.advance(to: 10)
        engine.ingest(.near, at: 10)

        XCTAssertEqual(engine.snapshot.phase, .cancelled)
        XCTAssertEqual(engine.snapshot.progress, 0.25, accuracy: 0.000_001)

        engine.reset(at: 10)
        XCTAssertEqual(engine.snapshot.phase, .idle)
        XCTAssertEqual(engine.snapshot.progress, 0, accuracy: 0.000_001)
    }

    func testReduceMotionChangesPresentationContractNotExposureMath() {
        var engine = TemporalDarkroomEngine(policy: policy)
        engine.reset(at: 0)
        engine.setProcessingActive(true, at: 0)
        engine.ingest(.near, at: 0)
        engine.advance(to: 0.5)
        let progressBeforeChange = engine.snapshot.progress

        engine.setReduceMotion(true)

        XCTAssertEqual(
            engine.snapshot.progress,
            progressBeforeChange,
            accuracy: 0.000_001
        )
        XCTAssertFalse(engine.snapshot.shouldAnimateProgress)
    }

    func testStaleObservationCannotRewindTheTimeline() {
        var engine = TemporalDarkroomEngine(policy: policy)
        engine.reset(at: 10)
        engine.setProcessingActive(true, at: 10)
        engine.ingest(.near, at: 10)
        engine.advance(to: 11)

        engine.ingest(.far, at: 9)

        XCTAssertEqual(engine.snapshot.inputState, .near)
        XCTAssertEqual(engine.snapshot.progress, 0.5, accuracy: 0.000_001)
    }

    func testNonFiniteTimestampsAndPolicyValuesCannotPoisonState() {
        let invalidPolicy = TemporalDarkroomPolicy(
            requiredExposureDuration: .nan,
            departureHoldDuration: .infinity,
            decayPerSecond: -.infinity,
            normalTickInterval: .nan,
            reduceMotionTickInterval: .infinity
        )
        var engine = TemporalDarkroomEngine(policy: invalidPolicy)
        engine.reset(at: 0)
        engine.setProcessingActive(true, at: 0)
        engine.ingest(.near, at: 0)
        engine.advance(to: 1)
        let progress = engine.snapshot.progress

        engine.ingest(.far, at: .nan)
        engine.advance(to: .infinity)
        engine.setProcessingActive(false, at: -.infinity)

        XCTAssertTrue(engine.snapshot.progress.isFinite)
        XCTAssertEqual(engine.snapshot.progress, progress, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.inputState, .near)
        XCTAssertTrue(engine.snapshot.isProcessingActive)
        XCTAssertTrue(invalidPolicy.requiredExposureDuration.isFinite)
        XCTAssertTrue(invalidPolicy.departureHoldDuration.isFinite)
        XCTAssertTrue(invalidPolicy.decayPerSecond.isFinite)
    }
}

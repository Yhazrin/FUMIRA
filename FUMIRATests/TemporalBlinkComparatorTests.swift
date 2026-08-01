import XCTest
@testable import FUMIRA

final class TemporalBlinkComparatorTests: XCTestCase {
    private let engine = TemporalBlinkComparatorEngine.standard

    func testHoldTemporarilyRevealsOriginalWithoutChangingLockedFrame() {
        XCTAssertEqual(
            engine.visibleFrame(
                lockedFrame: .generated,
                isHoldingOriginal: false,
                cadenceFrame: nil
            ),
            .generated
        )
        XCTAssertEqual(
            engine.visibleFrame(
                lockedFrame: .generated,
                isHoldingOriginal: true,
                cadenceFrame: nil
            ),
            .original
        )
        XCTAssertEqual(engine.toggled(.generated), .original)
        XCTAssertEqual(engine.toggled(.original), .generated)
    }

    func testManualHoldTakesPriorityOverCadence() {
        XCTAssertEqual(
            engine.visibleFrame(
                lockedFrame: .generated,
                isHoldingOriginal: true,
                cadenceFrame: .generated
            ),
            .original
        )
    }

    func testBlinkPlanIsFiniteSlowAndReturnsToStartingFrame() throws {
        let plan = engine.blinkPlan(
            startingFrom: .generated,
            reduceMotion: false,
            dimFlashingLights: false
        )

        XCTAssertEqual(plan.map(\.frame), [.original, .generated, .original, .generated])
        XCTAssertEqual(try XCTUnwrap(plan.first).delay, .zero)
        XCTAssertEqual(plan.count, 4)
        for step in plan.dropFirst() {
            XCTAssertGreaterThanOrEqual(
                step.delay,
                TemporalBlinkComparatorEngine.minimumDwell
            )
        }
    }

    func testUnsafeRequestedDwellIsRaisedToSafetyFloor() {
        let engine = TemporalBlinkComparatorEngine(dwell: .milliseconds(20))

        XCTAssertEqual(engine.dwell, TemporalBlinkComparatorEngine.minimumDwell)
    }

    func testAccessibilityPreferencesDisableCadenceButNotManualToggle() {
        XCTAssertTrue(engine.blinkPlan(
            startingFrom: .generated,
            reduceMotion: true,
            dimFlashingLights: false
        ).isEmpty)
        XCTAssertTrue(engine.blinkPlan(
            startingFrom: .generated,
            reduceMotion: false,
            dimFlashingLights: true
        ).isEmpty)
        XCTAssertEqual(engine.toggled(.generated), .original)
    }

    func testComponentControlMeetsMinimumTouchTarget() {
        XCTAssertGreaterThanOrEqual(
            TemporalBlinkComparatorMetrics.minimumTarget,
            44
        )
    }

    func testEngineAndPlanValuesAreSendable() {
        assertSendable(engine)
        assertSendable(engine.blinkPlan(
            startingFrom: .generated,
            reduceMotion: false,
            dimFlashingLights: false
        ))
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

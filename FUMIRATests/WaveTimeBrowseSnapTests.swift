import XCTest
@testable import FUMIRA

final class WaveTimeBrowseSnapTests: XCTestCase {
    func testNearNowSnapsToWholeDays() {
        let raw = TimePosition(offsetDays: 3.4)
        let snapped = WaveTimeBrowseSnap.snap(raw)
        XCTAssertEqual(snapped.offsetDays, 3, accuracy: 0.000_001)
    }

    func testNowBandSnapsToNow() {
        let snapped = WaveTimeBrowseSnap.snap(TimePosition(offsetDays: 0.2))
        XCTAssertEqual(snapped.normalized, 0, accuracy: 0.000_001)
    }

    func testMidRangeSnapsToWeeks() {
        let raw = TimePosition(offsetDays: 40)
        let snapped = WaveTimeBrowseSnap.snap(raw)
        // Nonlinear TimePosition round-trip can leave sub-day FP noise.
        let weeks = snapped.offsetDays / 7
        XCTAssertEqual(weeks, weeks.rounded(), accuracy: 0.02)
        XCTAssertGreaterThan(abs(snapped.offsetDays), 31)
        XCTAssertLessThan(abs(snapped.offsetDays), 365.25)
    }

    func testFarRangeSnapsToYearsWithoutLandmarkAnchors() {
        let raw = TimePosition(offsetDays: 40 * 365.25)
        let snapped = WaveTimeBrowseSnap.snap(raw)
        let years = snapped.offsetYears
        XCTAssertEqual(years, years.rounded(), accuracy: 0.000_001)
        // Must not force the historic five-point anchors.
        XCTAssertNotEqual(snapped.normalized, 0, accuracy: 0.000_001)
        XCTAssertNotEqual(abs(snapped.normalized), 1, accuracy: 0.000_001)
    }

    func testEndpointsRemainReachableAfterSnap() {
        XCTAssertEqual(WaveTimeBrowseSnap.snap(TimePosition(normalized: -1)).offsetYears, -100, accuracy: 0.001)
        XCTAssertEqual(WaveTimeBrowseSnap.snap(TimePosition(normalized: 1)).offsetYears, 100, accuracy: 0.001)
    }

    func testSnapPreservesNonlinearFinenessNearNow() {
        let nearNow = WaveTimeBrowseSnap.snap(TimePosition(normalized: 0.05))
        let nearEnd = WaveTimeBrowseSnap.snap(TimePosition(normalized: 0.95))
        XCTAssertLessThan(abs(nearNow.offsetDays), abs(nearEnd.offsetDays))
    }

    func testVerticalPullMovesThroughFineGranularities() {
        XCTAssertEqual(
            WaveTimeGranularity.year.offsetting(verticalTranslation: -29),
            .month
        )
        XCTAssertEqual(
            WaveTimeGranularity.month.offsetting(verticalTranslation: -57),
            .hour
        )
        XCTAssertEqual(
            WaveTimeGranularity.hour.offsetting(verticalTranslation: 84),
            .year
        )
    }

    func testFinerGranularityMovesOneStepAndHoldsAtHour() {
        XCTAssertEqual(WaveTimeGranularity.year.finer, .month)
        XCTAssertEqual(WaveTimeGranularity.month.finer, .day)
        XCTAssertEqual(WaveTimeGranularity.day.finer, .hour)
        XCTAssertEqual(WaveTimeGranularity.hour.finer, .hour)
    }

    func testCoarserGranularityMovesOneStepAndHoldsAtYear() {
        XCTAssertEqual(WaveTimeGranularity.hour.coarser, .day)
        XCTAssertEqual(WaveTimeGranularity.day.coarser, .month)
        XCTAssertEqual(WaveTimeGranularity.month.coarser, .year)
        XCTAssertEqual(WaveTimeGranularity.year.coarser, .year)
    }

    func testHourGranularitySnapsToWholeHour() {
        let raw = TimePosition(offsetDays: 2.0 + 37.0 / (24 * 60))
        let snapped = WaveTimeBrowseSnap.snap(raw, granularity: .hour)
        XCTAssertEqual(snapped.offsetDays * 24, 49, accuracy: 0.000_001)
    }

    func testFineHorizontalWindowsAreProgressivelyNarrower() {
        XCTAssertGreaterThan(
            WaveTimeGranularity.month.horizontalWindowDays,
            WaveTimeGranularity.day.horizontalWindowDays
        )
        XCTAssertGreaterThan(
            WaveTimeGranularity.day.horizontalWindowDays,
            WaveTimeGranularity.hour.horizontalWindowDays
        )
    }

    @MainActor
    func testDefaultExternalValueUpdatesKeepExistingSettleAnimation() {
        _ = WaveTimeRail(value: 0) { _ in }
        _ = WaveTimeRail(value: 0, isExternalValueDirectDriven: true) { _ in }

        XCTAssertTrue(
            WaveTimeRailValueAnimationPolicy.shouldAnimate(
                isDragging: false,
                reduceMotion: false,
                isExternalValueDirectDriven: false,
                isReleasePresentationActive: false
            )
        )
    }

    func testExternalDirectDriveDisablesImplicitValueSettle() {
        XCTAssertFalse(
            WaveTimeRailValueAnimationPolicy.shouldAnimate(
                isDragging: false,
                reduceMotion: false,
                isExternalValueDirectDriven: true,
                isReleasePresentationActive: false
            )
        )
    }

    func testExternalDirectDrivePreservesLocalReleasePresentation() {
        XCTAssertTrue(
            WaveTimeRailValueAnimationPolicy.shouldAnimate(
                isDragging: false,
                reduceMotion: false,
                isExternalValueDirectDriven: true,
                isReleasePresentationActive: true
            )
        )
    }

    func testDraggingAndReduceMotionNeverImplicitlySettle() {
        XCTAssertFalse(
            WaveTimeRailValueAnimationPolicy.shouldAnimate(
                isDragging: true,
                reduceMotion: false,
                isExternalValueDirectDriven: false,
                isReleasePresentationActive: true
            )
        )
        XCTAssertFalse(
            WaveTimeRailValueAnimationPolicy.shouldAnimate(
                isDragging: false,
                reduceMotion: true,
                isExternalValueDirectDriven: false,
                isReleasePresentationActive: true
            )
        )
    }
}

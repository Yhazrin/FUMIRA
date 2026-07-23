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
}

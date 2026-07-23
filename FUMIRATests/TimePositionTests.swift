import XCTest
@testable import FUMIRA

final class TimePositionTests: XCTestCase {
    func testEndpointsAreExactlyOneHundredYears() {
        XCTAssertEqual(TimePosition(normalized: -1).offsetYears, -100, accuracy: 0.000_001)
        XCTAssertEqual(TimePosition(normalized: 1).offsetYears, 100, accuracy: 0.000_001)
    }

    func testMappingIsSymmetricAndReversible() {
        let value = TimePosition(normalized: 0.42)
        XCTAssertEqual(value.offsetDays, -TimePosition(normalized: -0.42).offsetDays, accuracy: 0.000_001)
        XCTAssertEqual(TimePosition(offsetDays: value.offsetDays).normalized, 0.42, accuracy: 0.000_001)
    }

    func testEqualRailMovementIsFinerNearNow() {
        let nearNowDelta = TimePosition(normalized: 0.1).offsetDays - TimePosition(normalized: 0).offsetDays
        let nearEndDelta = TimePosition(normalized: 1).offsetDays - TimePosition(normalized: 0.9).offsetDays
        XCTAssertLessThan(nearNowDelta, nearEndDelta)
    }

    func testBoundsAreClamped() {
        XCTAssertEqual(TimePosition(normalized: 2).normalized, 1)
        XCTAssertEqual(TimePosition(normalized: -2).normalized, -1)
    }
}

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

    func testExactTimeIdentityAllowsOffsetDaysRoundTripButRejectsOneHour() {
        let original = TimePosition(offsetDays: 8_765.25)
        let roundTripped = TimePosition(offsetDays: original.offsetDays)

        XCTAssertTrue(
            original.hasSameExactTimeIdentity(asOffsetDays: roundTripped.offsetDays)
        )
        XCTAssertTrue(
            original.hasSameExactTimeIdentity(
                asOffsetDays: original.offsetDays + 0.5 / (24 * 60 * 60)
            )
        )
        XCTAssertFalse(
            original.hasSameExactTimeIdentity(
                asOffsetDays: original.offsetDays + 1.0 / 24.0
            )
        )
    }

    func testResultBrowseOneHourAwayIsNotTheGeneratedFrame() {
        let generated = TimePosition(offsetDays: 4_321.25)
        let browsed = TimePosition(offsetDays: generated.offsetDays + 1.0 / 24.0)

        XCTAssertFalse(
            ResultBrowseFrameIdentity.isGenerated(
                browsedTime: browsed,
                generatedTime: generated
            )
        )
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

    func testTargetDatePreservesHourPrecision() {
        let reference = Date(timeIntervalSince1970: 1_000_000)
        let target = TimePosition(offsetDays: 1.0 / 24.0)
            .targetDate(from: reference)
        XCTAssertEqual(target.timeIntervalSince(reference), 3_600, accuracy: 0.001)
    }

    func testCompactLabelCanDescribeHours() {
        XCTAssertEqual(TimePosition(offsetDays: 3.0 / 24.0).compactLabel, "3 小时后")
        XCTAssertEqual(TimePosition(offsetDays: -2.0 / 24.0).compactLabel, "2 小时前")
    }

    func testTrackedSubjectClampsAndSmoothsNormalizedGeometry() {
        let source = CameraTrackedSubject(
            normalizedX: -1,
            normalizedY: 2,
            normalizedWidth: 0.4,
            normalizedHeight: 0.5,
            confidence: 2
        )
        XCTAssertEqual(source.normalizedX, 0)
        XCTAssertEqual(source.normalizedY, 0.5)
        XCTAssertEqual(source.confidence, 1)

        let target = CameraTrackedSubject(
            normalizedX: 0.4,
            normalizedY: 0.2,
            normalizedWidth: 0.2,
            normalizedHeight: 0.3,
            confidence: 0.8
        )
        let smoothed = source.smoothed(toward: target, response: 0.25)
        XCTAssertEqual(smoothed.normalizedX, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(smoothed.normalizedWidth, 0.35, accuracy: 0.000_001)
    }

    func testTrackedSubjectFocusesOnCoreWhileKeepingCenter() {
        let source = CameraTrackedSubject(
            normalizedX: 0.1,
            normalizedY: 0.1,
            normalizedWidth: 0.8,
            normalizedHeight: 0.9,
            confidence: 0.8
        )
        let focused = source.focused(
            horizontalScale: 0.36,
            verticalScale: 0.40,
            maximumWidth: 0.24,
            maximumHeight: 0.28
        )

        XCTAssertEqual(focused.center.x, source.center.x, accuracy: 0.000_001)
        XCTAssertEqual(focused.center.y, source.center.y, accuracy: 0.000_001)
        XCTAssertEqual(focused.normalizedWidth, 0.24, accuracy: 0.000_001)
        XCTAssertEqual(focused.normalizedHeight, 0.28, accuracy: 0.000_001)
    }

    func testTrackedSubjectUsesAdaptiveResponsesForFastAndCalmMovement() {
        XCTAssertEqual(
            CameraTrackedSubject.trackingResponse(forCenterDistance: 0.02),
            0.16,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CameraTrackedSubject.trackingResponse(forCenterDistance: 0.09),
            0.38,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CameraTrackedSubject.trackingResponse(forCenterDistance: 0.24),
            0.72,
            accuracy: 0.000_001
        )
    }
}

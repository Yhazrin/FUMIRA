import XCTest
@testable import FUMIRA

final class FlatMotionTests: XCTestCase {
    private let samples: [Double] = [-1, -0.73, -0.2, 0, 0.18, 0.62, 1]

    func testActivePeakIsUniqueAtRepresentativeValues() {
        for sample in samples {
            XCTAssertTrue(
                WaveformGeometry.isActivePeakUnique(normalized: sample),
                "Expected unique active peak at \(sample)"
            )
        }
    }

    func testOrdinaryBarsStayBelowActivePeak() {
        for sample in samples {
            let maxOrdinary = WaveformGeometry.maxOrdinaryHeight(normalized: sample)
            XCTAssertLessThan(
                maxOrdinary,
                WaveformGeometry.activePeakRatio,
                "Ordinary bars must stay below active peak at \(sample)"
            )
        }
    }

    func testNearbyValuesMorphContinuously() {
        let pairs: [(Double, Double)] = [
            (0, 0.01),
            (-0.4, -0.39),
            (0.82, 0.83)
        ]
        for (first, second) in pairs {
            let delta = WaveformGeometry.maxOrdinaryDelta(between: first, and: second)
            XCTAssertLessThan(delta, 0.08, "Heights should change smoothly between \(first) and \(second)")
        }
    }

    func testContinuousIndexTracksNormalizedValue() {
        XCTAssertEqual(WaveformGeometry.continuousIndex(normalized: -1), 0, accuracy: 0.000_001)
        XCTAssertEqual(
            WaveformGeometry.continuousIndex(normalized: 1),
            Double(WaveformGeometry.defaultBarCount - 1),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            WaveformGeometry.continuousIndex(normalized: 0),
            Double(WaveformGeometry.defaultBarCount - 1) / 2,
            accuracy: 0.000_001
        )
    }
}

final class WaveTimeAccessibilityTests: XCTestCase {
    func testNowAdjustsByOneDayInEachDirection() {
        let plusOne = WaveTimeAccessibilityAdjustment.adjustedOffsetDays(
            from: 0,
            direction: .increment
        )
        let minusOne = WaveTimeAccessibilityAdjustment.adjustedOffsetDays(
            from: 0,
            direction: .decrement
        )
        XCTAssertEqual(plusOne, 1, accuracy: 0.000_001)
        XCTAssertEqual(minusOne, -1, accuracy: 0.000_001)
        XCTAssertNotEqual(plusOne, 0)
        XCTAssertNotEqual(minusOne, 0)
    }

    func testVoiceOverAdjustmentClampsAtEndpoints() {
        let maxDays = TimePosition.maximumOffsetDays
        let atMax = WaveTimeAccessibilityAdjustment.adjustedOffsetDays(
            from: maxDays,
            direction: .increment
        )
        let atMin = WaveTimeAccessibilityAdjustment.adjustedOffsetDays(
            from: -maxDays,
            direction: .decrement
        )
        XCTAssertEqual(atMax, maxDays, accuracy: 0.000_001)
        XCTAssertEqual(atMin, -maxDays, accuracy: 0.000_001)
    }

    func testHapticCrossingFiresForNowAndDecades() {
        XCTAssertTrue(WaveTimeHapticCrossing.shouldTick(previousYears: -0.2, currentYears: 0.1))
        XCTAssertTrue(WaveTimeHapticCrossing.shouldTick(previousYears: 9.4, currentYears: 10.6))
        XCTAssertTrue(WaveTimeHapticCrossing.shouldTick(previousYears: -11.2, currentYears: -9.1))
        XCTAssertFalse(WaveTimeHapticCrossing.shouldTick(previousYears: 4.2, currentYears: 4.8))
        XCTAssertFalse(WaveTimeHapticCrossing.shouldTick(previousYears: 0.1, currentYears: 0.8))
    }

    func testHapticBaselineDoesNotTickOnIdenticalSample() {
        XCTAssertFalse(WaveTimeHapticCrossing.shouldTick(previousYears: 12, currentYears: 12.2))
    }
}

final class WaveTimeHapticBucketTests: XCTestCase {
    func testSignedDecadeBuckets() {
        XCTAssertEqual(WaveTimeHapticCrossing.bucket(for: 0.1), 0)
        XCTAssertEqual(WaveTimeHapticCrossing.bucket(for: 9.4), 0)
        XCTAssertEqual(WaveTimeHapticCrossing.bucket(for: 12.4), 10)
        XCTAssertEqual(WaveTimeHapticCrossing.bucket(for: -9.1), 0)
        XCTAssertEqual(WaveTimeHapticCrossing.bucket(for: -23.1), -20)
    }
}

final class WaveTimeRollPhysicsTests: XCTestCase {
    func testReleaseDirectionFollowsPredictedTravel() {
        XCTAssertEqual(WaveTimeRollPhysics.releaseDirection(current: 0.2, predicted: 0.4), 1)
        XCTAssertEqual(WaveTimeRollPhysics.releaseDirection(current: 0.2, predicted: -0.1), -1)
        XCTAssertEqual(WaveTimeRollPhysics.releaseDirection(current: 0.2, predicted: 0.2), 0)
    }

    func testReleaseKickIsBounded() {
        XCTAssertEqual(WaveTimeRollPhysics.releaseKick(current: 0.2, predicted: 0.2), 0)
        XCTAssertGreaterThan(WaveTimeRollPhysics.releaseKick(current: 0.2, predicted: 0.24), 0)
        XCTAssertEqual(
            WaveTimeRollPhysics.releaseKick(current: -1, predicted: 1),
            WaveTimeRollPhysics.maximumKick,
            accuracy: 0.000_001
        )
    }

    func testOvershootNeverLeavesTimeRange() {
        XCTAssertEqual(
            WaveTimeRollPhysics.overshoot(target: 1, direction: 1, kick: 0.018),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            WaveTimeRollPhysics.overshoot(target: -1, direction: -1, kick: 0.018),
            -1,
            accuracy: 0.000_001
        )
    }
}

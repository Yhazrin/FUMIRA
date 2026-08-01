import XCTest
@testable import FUMIRA

final class TiltTimeNavigatorTests: XCTestCase {
    private let navigator = TiltTimeNavigator.standard

    func testDeadZoneStopsNavigation() {
        let position = TimePosition(normalized: 0.23)

        XCTAssertEqual(
            navigator.advance(position, rollRadians: 0, frameDelta: 1.0 / 60).normalized,
            position.normalized
        )
        XCTAssertEqual(
            navigator.advance(
                position,
                rollRadians: navigator.deadZoneRadians,
                frameDelta: 1.0 / 60
            ).normalized,
            position.normalized
        )
        XCTAssertEqual(
            navigator.advance(
                position,
                rollRadians: -navigator.deadZoneRadians,
                frameDelta: 1.0 / 60
            ).normalized,
            position.normalized
        )
    }

    func testRollDirectionMovesLeftToPastAndRightToFuture() {
        let position = TimePosition.now
        let past = navigator.advance(position, rollRadians: -0.3, frameDelta: 1.0 / 60)
        let future = navigator.advance(position, rollRadians: 0.3, frameDelta: 1.0 / 60)

        XCTAssertLessThan(past.normalized, position.normalized)
        XCTAssertGreaterThan(future.normalized, position.normalized)
        XCTAssertEqual(past.normalized, -future.normalized, accuracy: 0.000_001)
    }

    func testStrongerTiltProducesHigherSpeed() {
        let gentleSpeed = navigator.normalizedVelocity(for: 0.16)
        let strongSpeed = navigator.normalizedVelocity(for: 0.42)

        XCTAssertGreaterThan(gentleSpeed, 0)
        XCTAssertGreaterThan(strongSpeed, gentleSpeed)
        XCTAssertLessThanOrEqual(strongSpeed, navigator.maximumNormalizedVelocity)
    }

    func testEquivalentElapsedTimeIsFrameRateIndependent() {
        let thirtyFPS = advance(rollRadians: 0.34, frameCount: 30, frameDelta: 1.0 / 30)
        let sixtyFPS = advance(rollRadians: 0.34, frameCount: 60, frameDelta: 1.0 / 60)

        XCTAssertEqual(thirtyFPS.normalized, sixtyFPS.normalized, accuracy: 0.000_001)
    }

    func testAdvancePreservesContinuousPositionWithoutSnapping() {
        let position = TimePosition(normalized: 0.123_456)
        let frameDelta = 1.0 / 60
        let next = navigator.advance(position, rollRadians: 0.27, frameDelta: frameDelta)
        let expected = position.normalized
            + navigator.normalizedVelocity(for: 0.27) * frameDelta

        XCTAssertEqual(next.normalized, expected, accuracy: 0.000_000_001)
        XCTAssertNotEqual(next.normalized, 0, accuracy: 0.000_001)
        XCTAssertNotEqual(next.normalized, 0.5, accuracy: 0.000_001)
        XCTAssertNotEqual(next.normalized, 1, accuracy: 0.000_001)
    }

    func testPositionsClampAtBothEndpoints() {
        let future = navigator.advance(
            TimePosition(normalized: 0.99),
            rollRadians: navigator.fullSpeedTiltRadians,
            frameDelta: navigator.maximumFrameDelta
        )
        let past = navigator.advance(
            TimePosition(normalized: -0.99),
            rollRadians: -navigator.fullSpeedTiltRadians,
            frameDelta: navigator.maximumFrameDelta
        )

        XCTAssertEqual(future.normalized, 1)
        XCTAssertEqual(past.normalized, -1)
    }

    func testNonfiniteSamplesAndInvalidFrameDeltasAreSafe() {
        let position = TimePosition(normalized: 0.17)

        for roll in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                navigator.advance(position, rollRadians: roll, frameDelta: 1.0 / 60),
                position
            )
            XCTAssertEqual(navigator.normalizedVelocity(for: roll), 0)
        }

        for delta in [Double.nan, .infinity, -.infinity, -0.01, 0] {
            XCTAssertEqual(
                navigator.advance(position, rollRadians: 0.3, frameDelta: delta),
                position
            )
        }
    }

    func testLongFrameDeltaIsBounded() {
        let position = TimePosition.now
        let bounded = navigator.advance(
            position,
            rollRadians: 0.3,
            frameDelta: navigator.maximumFrameDelta
        )
        let stalledFrame = navigator.advance(position, rollRadians: 0.3, frameDelta: 10)

        XCTAssertEqual(stalledFrame.normalized, bounded.normalized, accuracy: 0.000_001)
    }

    private func advance(
        rollRadians: Double,
        frameCount: Int,
        frameDelta: TimeInterval
    ) -> TimePosition {
        (0..<frameCount).reduce(.now) { position, _ in
            navigator.advance(position, rollRadians: rollRadians, frameDelta: frameDelta)
        }
    }
}

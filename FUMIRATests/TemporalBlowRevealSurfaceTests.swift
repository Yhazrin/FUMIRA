import XCTest
@testable import FUMIRA

final class TemporalBlowRevealSurfaceTests: XCTestCase {
    func testResolveClampsProgressAndGust() {
        let presentation = TemporalBlowRevealPresentation.resolve(
            progress: 4,
            gust: -3,
            reduceMotion: false
        )

        XCTAssertEqual(presentation.progress, 1)
        XCTAssertEqual(presentation.gust, 0)
        XCTAssertEqual(presentation.remainingFraction, 0)
        XCTAssertEqual(presentation.revealedPercentage, 100)
        XCTAssertEqual(presentation.targetLabelOpacity, 1)
    }

    func testResolveTreatsNonFiniteInputAsResting() {
        let presentation = TemporalBlowRevealPresentation.resolve(
            progress: .nan,
            gust: .infinity,
            reduceMotion: false
        )

        XCTAssertEqual(presentation.progress, 0)
        XCTAssertEqual(presentation.gust, 0)
        XCTAssertEqual(presentation.remainingFraction, 1)
        XCTAssertEqual(presentation.revealedPercentage, 0)
        XCTAssertFalse(presentation.showsParticles)
    }

    func testStandardMotionUsesOneProgressDrivenPaperPose() {
        let presentation = TemporalBlowRevealPresentation.resolve(
            progress: 0.5,
            gust: 1,
            reduceMotion: false
        )

        XCTAssertEqual(presentation.remainingFraction, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(presentation.paperLift, 0)
        XCTAssertLessThan(presentation.paperBendDegrees, 0)
        XCTAssertGreaterThan(presentation.edgeCurl, 0)
        XCTAssertGreaterThan(presentation.paperShadowOpacity, 0)
        XCTAssertGreaterThan(presentation.particleIntensity, 0)
        XCTAssertTrue(presentation.showsParticles)
    }

    func testReduceMotionUsesOnlyMaskAndFade() {
        let presentation = TemporalBlowRevealPresentation.resolve(
            progress: 0.5,
            gust: 1,
            reduceMotion: true
        )

        XCTAssertEqual(presentation.remainingFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(presentation.originalOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(presentation.paperLift, 0)
        XCTAssertEqual(presentation.paperBendDegrees, 0)
        XCTAssertEqual(presentation.edgeCurl, 0)
        XCTAssertEqual(presentation.paperShadowOpacity, 0)
        XCTAssertEqual(presentation.particleIntensity, 0)
        XCTAssertFalse(presentation.showsParticles)
    }

    func testGustChangesEffectsWithoutChangingRevealGeometry() {
        let quiet = TemporalBlowRevealPresentation.resolve(
            progress: 0.5,
            gust: 0,
            reduceMotion: false
        )
        let gusty = TemporalBlowRevealPresentation.resolve(
            progress: 0.5,
            gust: 1,
            reduceMotion: false
        )

        XCTAssertEqual(quiet.remainingFraction, gusty.remainingFraction)
        XCTAssertEqual(quiet.targetLabelOpacity, gusty.targetLabelOpacity)
        XCTAssertEqual(quiet.paperLift, 0)
        XCTAssertGreaterThan(gusty.paperLift, quiet.paperLift)
        XCTAssertGreaterThan(gusty.particleIntensity, quiet.particleIntensity)
    }

    func testCompletedRevealRemovesPaperAndParticles() {
        let presentation = TemporalBlowRevealPresentation.resolve(
            progress: 1,
            gust: 1,
            reduceMotion: false
        )

        XCTAssertEqual(presentation.remainingFraction, 0)
        XCTAssertEqual(presentation.originalOpacity, 0)
        XCTAssertEqual(presentation.particleIntensity, 0)
        XCTAssertFalse(presentation.showsParticles)
        XCTAssertEqual(presentation.targetLabelOpacity, 1)
    }
}

import XCTest
@testable import FUMIRA

@MainActor
final class BlowRevealEngineTests: XCTestCase {
    private let policy = BlowRevealPolicy(
        noiseGateDecibels: -40,
        fullGustDecibels: -10,
        attackTimeConstant: 0.1,
        releaseTimeConstant: 0.2,
        revealGainPerSecond: 1,
        revealDecayPerSecond: 0.25,
        activeGustThreshold: 0.1
    )

    func testNoiseGateSuppressesAmbientInput() {
        var engine = BlowRevealEngine(policy: policy)
        engine.reset(at: 0)
        engine.ingest(decibels: -55, at: 0.1)

        XCTAssertEqual(engine.snapshot.rawGust, 0, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.gust, 0, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.revealProgress, 0, accuracy: 0.000_001)
    }

    func testDecibelMappingIsBoundedAndMonotonic() {
        let quiet = policy.normalizedGust(for: -40)
        let medium = policy.normalizedGust(for: -25)
        let strong = policy.normalizedGust(for: -10)

        XCTAssertEqual(quiet, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(medium, quiet)
        XCTAssertLessThan(medium, strong)
        XCTAssertEqual(strong, 1, accuracy: 0.000_001)
        XCTAssertEqual(policy.normalizedGust(for: -.infinity), 0)
        XCTAssertEqual(policy.normalizedGust(for: .infinity), 1)
        XCTAssertEqual(policy.normalizedGust(for: .nan), 0)
    }

    func testAttackSmoothsStrongInput() {
        var engine = BlowRevealEngine(policy: policy)
        engine.reset(at: 0)
        engine.ingest(decibels: -10, at: 0.1)

        XCTAssertGreaterThan(engine.snapshot.gust, 0)
        XCTAssertLessThan(engine.snapshot.gust, 1)
        XCTAssertGreaterThan(engine.snapshot.revealProgress, 0)
    }

    func testSustainedBlowAccumulatesAndCompletionIsSticky() {
        var engine = BlowRevealEngine(policy: policy)
        engine.reset(at: 0)
        for index in 1...30 {
            engine.ingest(decibels: -8, at: Double(index) * 0.1)
        }

        XCTAssertTrue(engine.snapshot.isRevealed)
        XCTAssertEqual(engine.snapshot.revealProgress, 1, accuracy: 0.000_001)

        engine.advance(to: 100)
        XCTAssertEqual(engine.snapshot.revealProgress, 1, accuracy: 0.000_001)
    }

    func testSilenceReleasesGustAndDecaysPartialReveal() {
        var engine = BlowRevealEngine(policy: policy)
        engine.reset(at: 0)
        for index in 1...5 {
            engine.ingest(decibels: -10, at: Double(index) * 0.1)
        }
        let partialProgress = engine.snapshot.revealProgress
        let activeGust = engine.snapshot.gust

        engine.advance(to: 1.5)

        XCTAssertLessThan(engine.snapshot.gust, activeGust)
        XCTAssertLessThan(engine.snapshot.revealProgress, partialProgress)
        XCTAssertGreaterThanOrEqual(engine.snapshot.revealProgress, 0)
    }

    func testStaleAndNonFiniteTimestampsCannotPoisonState() {
        var engine = BlowRevealEngine(policy: policy)
        engine.reset(at: 10)
        engine.ingest(decibels: -10, at: 11)
        let snapshot = engine.snapshot

        engine.ingest(decibels: -10, at: 9)
        engine.ingest(decibels: .nan, at: .nan)
        engine.advance(to: .infinity)

        XCTAssertEqual(engine.snapshot, snapshot)
        XCTAssertTrue(engine.snapshot.gust.isFinite)
        XCTAssertTrue(engine.snapshot.revealProgress.isFinite)
    }

    func testInvalidPolicyValuesAreSanitized() {
        let invalid = BlowRevealPolicy(
            noiseGateDecibels: .nan,
            fullGustDecibels: -.infinity,
            attackTimeConstant: .nan,
            releaseTimeConstant: .infinity,
            revealGainPerSecond: -.infinity,
            revealDecayPerSecond: .nan,
            activeGustThreshold: .infinity
        )

        XCTAssertTrue(invalid.noiseGateDecibels.isFinite)
        XCTAssertTrue(invalid.fullGustDecibels.isFinite)
        XCTAssertGreaterThan(invalid.fullGustDecibels, invalid.noiseGateDecibels)
        XCTAssertGreaterThan(invalid.attackTimeConstant, 0)
        XCTAssertGreaterThan(invalid.releaseTimeConstant, 0)
        XCTAssertGreaterThanOrEqual(invalid.revealGainPerSecond, 0)
        XCTAssertGreaterThanOrEqual(invalid.revealDecayPerSecond, 0)
        XCTAssertGreaterThan(invalid.activeGustThreshold, 0)
        XCTAssertLessThanOrEqual(invalid.activeGustThreshold, 1)
    }

    func testMockPermissionDenialPublishesFallback() async {
        let service = MockBlowInputService(
            availability: .fallbackRequired(.microphonePermissionDenied)
        )
        var iterator = service.events().makeAsyncIterator()
        service.start()

        let event = await iterator.next()
        XCTAssertEqual(
            event,
            .availability(.fallbackRequired(.microphonePermissionDenied))
        )
    }

    func testMockPublishesRawLevelWithoutRetainingAudio() async {
        let service = MockBlowInputService()
        var iterator = service.events().makeAsyncIterator()
        service.start()
        _ = await iterator.next()
        service.emit(decibels: -18, at: 4)

        let levelEvent = await iterator.next()
        XCTAssertEqual(
            levelEvent,
            .level(BlowInputLevelSample(decibels: -18, timestamp: 4))
        )
        service.stop()
    }
}

import XCTest
@testable import FUMIRA

@MainActor
final class TemporalDarkroomServiceTests: XCTestCase {
    func testMockPublishesAvailabilityAndAlternativeInputOnOneStream() async {
        let service = MockTemporalDarkroomService(
            availability: .alternativeInputRequired,
            clock: { 4 }
        )
        let stream = service.events()
        var iterator = stream.makeAsyncIterator()

        service.start()
        let availability = await iterator.next()
        let initialState = await iterator.next()
        service.setAlternativeInputActive(true, timestamp: 5)
        let alternativeState = await iterator.next()

        XCTAssertEqual(availability, .availability(.alternativeInputRequired))
        XCTAssertEqual(
            initialState,
            .observation(
                TemporalDarkroomObservation(
                    state: .far,
                    source: .alternative,
                    timestamp: 4
                )
            )
        )
        XCTAssertEqual(
            alternativeState,
            .observation(
                TemporalDarkroomObservation(
                    state: .near,
                    source: .alternative,
                    timestamp: 5
                )
            )
        )
        XCTAssertEqual(service.startCallCount, 1)

        service.stop()
        XCTAssertEqual(service.stopCallCount, 1)
    }

    func testMockIgnoresInputAfterStopAndCanRestartWithNewStream() async {
        let service = MockTemporalDarkroomService(clock: { 1 })
        _ = service.events()
        service.start()
        service.stop()
        service.setAlternativeInputActive(true, timestamp: 2)

        let restartedStream = service.events()
        var iterator = restartedStream.makeAsyncIterator()
        service.start()

        let availability = await iterator.next()
        XCTAssertEqual(availability, .availability(.alternativeInputRequired))
        XCTAssertEqual(service.startCallCount, 2)
    }
}

import UIKit
import XCTest
@testable import FUMIRA

@MainActor
final class TemporalShakeDeviceServiceTests: XCTestCase {
    func testMotionEndedBridgePublishesOnlyMotionShake() async {
        let service = DeviceTemporalShakeService()
        let stream = service.events()
        var iterator = stream.makeAsyncIterator()

        service.start()
        service.responderBridgeDidActivate(true)
        let availability = await iterator.next()
        XCTAssertEqual(
            availability,
            .availability(.motionShakeResponder)
        )

        service.forwardMotionEnded(.remoteControlPlay, timestamp: 6)
        service.forwardMotionEnded(.motionShake, timestamp: 7)
        let shakeEvent = await iterator.next()
        XCTAssertEqual(
            shakeEvent,
            .systemShakeEnded(timestamp: 7)
        )

        service.stop()
    }

    func testResponderActivationFailureRequiresFallbackAndFinishes() async {
        let service = DeviceTemporalShakeService()
        let stream = service.events()
        var iterator = stream.makeAsyncIterator()

        service.start()
        service.responderBridgeDidActivate(false)

        let availability = await iterator.next()
        XCTAssertEqual(
            availability,
            .availability(.fallbackRequired)
        )
        let end = await iterator.next()
        XCTAssertNil(end)
    }

    func testResponderCanAttachBeforeServiceStarts() async {
        let service = DeviceTemporalShakeService()
        service.responderBridgeDidActivate(true)
        let stream = service.events()
        var iterator = stream.makeAsyncIterator()

        service.start()

        let availability = await iterator.next()
        XCTAssertEqual(
            availability,
            .availability(.motionShakeResponder)
        )
        service.stop()
    }
}

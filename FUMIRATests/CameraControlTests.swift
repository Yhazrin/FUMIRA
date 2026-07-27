import XCTest
@testable import FUMIRA

final class CameraControlTests: XCTestCase {
    func testFlashModeCyclesOffOnAuto() {
        XCTAssertEqual(CameraFlashMode.off.next, .on)
        XCTAssertEqual(CameraFlashMode.on.next, .auto)
        XCTAssertEqual(CameraFlashMode.auto.next, .off)
    }

    func testFlashModeAccessibilityLabelsAreLocalizedProductCopy() {
        XCTAssertFalse(CameraFlashMode.off.accessibilityLabel.contains("模型后台"))
        XCTAssertFalse(CameraFlashMode.on.accessibilityLabel.isEmpty)
        XCTAssertFalse(CameraFlashMode.auto.systemImageName.isEmpty)
    }

    func testZoomClampsToRecommendedHardwareRange() {
        let snapshot = CameraZoomSnapshot(
            factor: 2,
            displayFactor: 1,
            minimumFactor: 1,
            maximumFactor: 8
        )

        XCTAssertEqual(snapshot.clamping(0.5).factor, 1)
        XCTAssertEqual(snapshot.clamping(12).factor, 8)
        XCTAssertEqual(snapshot.clamping(4).factor, 4)
    }

    func testZoomClampingPreservesDisplayMultiplier() {
        let snapshot = CameraZoomSnapshot(
            factor: 2,
            displayFactor: 1,
            minimumFactor: 1,
            maximumFactor: 8
        )

        XCTAssertEqual(snapshot.clamping(6).displayFactor, 3)
    }

    func testUnavailableZoomHasNoAdjustableRange() {
        XCTAssertFalse(CameraZoomSnapshot.unavailable.isAvailable)
    }
}

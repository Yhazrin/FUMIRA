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
}

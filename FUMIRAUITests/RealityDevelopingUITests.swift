import XCTest

final class RealityDevelopingUITests: XCTestCase {
    @MainActor
    func testCapturedPhotoAcceptsDirectDrag() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "understanding"
        app.launch()

        let photo = app.otherElements["hero.hand-photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3))

        let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.34))
        start.press(forDuration: 0.12, thenDragTo: end)

        XCTAssertTrue(app.otherElements["reality.developing-stage"].exists)
    }

    @MainActor
    func testHorizontalInspectionRevealsMicroTimeSlice() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "understanding"
        app.launch()

        let stage = app.otherElements["reality.developing-stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 3))

        stage.swipeRight()

        let slice = app.otherElements["reality.temporal-slice"]
        XCTAssertTrue(slice.waitForExistence(timeout: 0.6))
        XCTAssertTrue(slice.label.contains("秒"))
    }

    @MainActor
    func testCancelReturnsFromUnderstandingToViewfinder() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "understanding"
        app.launch()

        let cancel = app.buttons["reality.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()

        let aspectControl = app.otherElements["viewfinder.aspect-control"]
        XCTAssertTrue(aspectControl.waitForExistence(timeout: 3))
    }
}

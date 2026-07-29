import XCTest

final class ResultRevealUITests: XCTestCase {
    @MainActor
    func testButtonFallbackOpensTimeDoor() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "result"
        app.launch()

        let revealButton = app.buttons["result.reveal-now"]
        XCTAssertTrue(revealButton.waitForExistence(timeout: 3))
        revealButton.tap()

        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: revealButton)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testRealityAlignmentReentersPreviewAndExposesTimeBoundary() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "result"
        app.launchEnvironment["FUMIRA_AUDIT_RESULT_REVEAL"] = "1"
        app.launch()

        let alignmentButton = app.buttons["对准现实"]
        XCTAssertTrue(alignmentButton.waitForExistence(timeout: 3))
        if !alignmentButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(alignmentButton.isHittable)
        alignmentButton.tap()

        let boundary = app.otherElements["result.reality-boundary"]
        XCTAssertTrue(boundary.waitForExistence(timeout: 3))
        boundary.swipeLeft()
        XCTAssertTrue(app.buttons["关闭现实对照"].exists)
    }
}

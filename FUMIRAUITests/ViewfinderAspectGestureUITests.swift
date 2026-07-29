import XCTest

final class ViewfinderAspectGestureUITests: XCTestCase {
    @MainActor
    func testCameraEntryAutoGrantReachesFullWidthViewfinder() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "connection"
        app.launchEnvironment["FUMIRA_AUDIT_CAMERA_ENTRY"] = "1"
        app.launchEnvironment["FUMIRA_AUDIT_AUTO_CAMERA_GRANT"] = "1"
        app.launchEnvironment["FUMIRA_AUDIT_DELAY_MS"] = "200"
        app.launch()

        let aspectControl = app.otherElements["viewfinder.aspect-control"]
        XCTAssertTrue(aspectControl.waitForExistence(timeout: 5))
        assertFullWidth(aspectControl, in: app)
    }

    @MainActor
    func testPinchInMovesTowardSquareComposition() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launchEnvironment["FUMIRA_AUDIT_ASPECT"] = "3:4"
        app.launch()

        let aspectControl = app.otherElements["viewfinder.aspect-control"]
        let waveControl = app.otherElements["viewfinder.shutter-wave"]
        XCTAssertTrue(aspectControl.waitForExistence(timeout: 3))
        XCTAssertTrue(waveControl.waitForExistence(timeout: 3))
        XCTAssertEqual(aspectControl.value as? String, "3:4")
        let initialWaveCenterY = waveControl.frame.midY

        aspectControl.pinch(withScale: 0.55, velocity: -2)

        let changed = NSPredicate(format: "value != %@", "3:4")
        expectation(for: changed, evaluatedWith: aspectControl)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(aspectControl.value as? String, "1:1")
        assertFullWidth(aspectControl, in: app)
        XCTAssertLessThan(waveControl.frame.midY, initialWaveCenterY)
    }

    @MainActor
    func testPinchOutMovesTowardFullScreenComposition() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launchEnvironment["FUMIRA_AUDIT_ASPECT"] = "3:4"
        app.launch()

        let aspectControl = app.otherElements["viewfinder.aspect-control"]
        let waveControl = app.otherElements["viewfinder.shutter-wave"]
        XCTAssertTrue(aspectControl.waitForExistence(timeout: 3))
        XCTAssertTrue(waveControl.waitForExistence(timeout: 3))
        XCTAssertEqual(aspectControl.value as? String, "3:4")

        aspectControl.pinch(withScale: 1.8, velocity: 2)

        let changed = NSPredicate(format: "value != %@", "3:4")
        expectation(for: changed, evaluatedWith: aspectControl)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(aspectControl.value as? String, "全屏")
        assertFullWidth(aspectControl, in: app)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(aspectControl.frame.minY, window.minY, accuracy: 1)
        XCTAssertEqual(aspectControl.frame.maxY, window.maxY, accuracy: 1)
        XCTAssertLessThan(waveControl.frame.maxY, window.maxY)
        XCTAssertTrue(aspectControl.frame.intersects(waveControl.frame))
    }

    @MainActor
    func testTapSelectsNarrativeSubjectInsideViewfinder() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launch()

        let interactionSurface = app.otherElements["viewfinder.aspect-control"]
        XCTAssertTrue(interactionSurface.waitForExistence(timeout: 3))

        interactionSurface
            .coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.38))
            .tap()

        let anchor = app.otherElements["viewfinder.subject-anchor"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 3))
        XCTAssertEqual(anchor.label, "时间主体已选择")
    }

    @MainActor
    func testLiveActivityButtonProvidesImmediateSystemFeedback() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launch()

        let button = app.buttons["显示实时相机状态"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: button
        )
        waitForExpectations(timeout: 2)
        button.tap()

        let feedback = app.descendants(matching: .any)
            .matching(identifier: "viewfinder.live-activity-feedback")
            .firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 2))
        XCTAssertTrue(feedback.label.contains("灵动岛"))
        XCTAssertGreaterThanOrEqual(
            feedback.frame.minY,
            button.frame.maxY + 7
        )
    }

    @MainActor
    func testTopCameraActionsKeepAppleScaleAndSymmetricInsets() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launch()

        let album = app.buttons["从相册导入"]
        let liveActivity = app.buttons["显示实时相机状态"]
        XCTAssertTrue(album.waitForExistence(timeout: 3))
        XCTAssertTrue(liveActivity.waitForExistence(timeout: 3))

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(album.frame.width, 44)
        XCTAssertGreaterThanOrEqual(album.frame.height, 44)
        XCTAssertGreaterThanOrEqual(liveActivity.frame.width, 44)
        XCTAssertGreaterThanOrEqual(liveActivity.frame.height, 44)
        XCTAssertEqual(album.frame.minX - window.minX, 16, accuracy: 1)
        XCTAssertEqual(window.maxX - liveActivity.frame.maxX, 16, accuracy: 1)
        XCTAssertEqual(album.frame.midY, liveActivity.frame.midY, accuracy: 1)
    }

    @MainActor
    private func assertFullWidth(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertEqual(
            element.frame.minX,
            windowFrame.minX,
            accuracy: 1,
            file: file,
            line: line
        )
        XCTAssertEqual(
            element.frame.maxX,
            windowFrame.maxX,
            accuracy: 1,
            file: file,
            line: line
        )
    }
}

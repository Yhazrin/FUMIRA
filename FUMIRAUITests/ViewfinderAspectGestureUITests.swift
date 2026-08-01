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
    func testSwipeUpMovesTowardSquareComposition() throws {
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

        dragAspectControl(aspectControl, from: 0.82, to: 0.48)

        let changed = NSPredicate(format: "value != %@", "3:4")
        expectation(for: changed, evaluatedWith: aspectControl)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(aspectControl.value as? String, "1:1")
        assertFullWidth(aspectControl, in: app)
        XCTAssertLessThan(waveControl.frame.midY, initialWaveCenterY)
    }

    @MainActor
    func testSwipeDownMovesTowardFullScreenComposition() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launchEnvironment["FUMIRA_AUDIT_ASPECT"] = "3:4"
        app.launch()

        let aspectControl = app.otherElements["viewfinder.aspect-control"]
        let waveControl = app.otherElements["viewfinder.shutter-wave"]
        XCTAssertTrue(aspectControl.waitForExistence(timeout: 3))
        XCTAssertTrue(waveControl.waitForExistence(timeout: 3))
        XCTAssertEqual(aspectControl.value as? String, "3:4")

        dragAspectControl(aspectControl, from: 0.72, to: 0.96)

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
    func testTapDoesNotCreateManualNarrativeSubject() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launch()

        let interactionSurface = app.otherElements["viewfinder.aspect-control"]
        XCTAssertTrue(interactionSurface.waitForExistence(timeout: 3))

        interactionSurface
            .coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.38))
            .tap()

        let anchor = app.otherElements["viewfinder.subject-anchor"]
        XCTAssertFalse(anchor.waitForExistence(timeout: 0.6))
    }

    @MainActor
    func testVerticalWavePullEntersHourGranularity() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launch()

        let wave = app.otherElements["viewfinder.shutter-wave"]
        XCTAssertTrue(wave.waitForExistence(timeout: 3))
        let start = wave.coordinate(
            withNormalizedOffset: CGVector(dx: 0.72, dy: 0.72)
        )
        let end = wave.coordinate(
            withNormalizedOffset: CGVector(dx: 0.78, dy: -0.55)
        )
        start.press(forDuration: 0.08, thenDragTo: end)

        let hourFormat = NSPredicate(format: "value CONTAINS ':'")
        expectation(for: hourFormat, evaluatedWith: wave)
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testFlipCameraButtonIsReachableInTopChrome() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launch()

        let button = app.buttons["翻转摄像头"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: button
        )
        waitForExpectations(timeout: 2)
        button.tap()
        XCTAssertTrue(button.exists)
    }

    @MainActor
    func testTopCameraActionsKeepAppleScaleAndSymmetricInsets() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "viewfinder"
        app.launch()

        let album = app.buttons["从相册导入"]
        let flipCamera = app.buttons["翻转摄像头"]
        XCTAssertTrue(album.waitForExistence(timeout: 3))
        XCTAssertTrue(flipCamera.waitForExistence(timeout: 3))

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(album.frame.width, 44)
        XCTAssertGreaterThanOrEqual(album.frame.height, 44)
        XCTAssertGreaterThanOrEqual(flipCamera.frame.width, 44)
        XCTAssertGreaterThanOrEqual(flipCamera.frame.height, 44)
        XCTAssertEqual(album.frame.minX - window.minX, 16, accuracy: 1)
        XCTAssertEqual(window.maxX - flipCamera.frame.maxX, 16, accuracy: 1)
        XCTAssertEqual(album.frame.midY, flipCamera.frame.midY, accuracy: 1)
    }

    @MainActor
    private func dragAspectControl(
        _ element: XCUIElement,
        from startY: CGFloat,
        to endY: CGFloat
    ) {
        let start = element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: startY)
        )
        let end = element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
        )
        start.press(forDuration: 0.08, thenDragTo: end)
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

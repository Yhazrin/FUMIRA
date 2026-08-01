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
    func testTurningPhotoRevealsQuestionAndRecordsAnswer() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "generating"
        app.launch()

        let photo = app.otherElements["hero.hand-photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3))

        let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        let end = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        start.press(forDuration: 0.12, thenDragTo: end)

        let reflection = app.otherElements["reality.reflection-card"]
        XCTAssertTrue(reflection.waitForExistence(timeout: 2))

        let answer = app.buttons["reality.reflection-option-future-encounter"]
        XCTAssertTrue(answer.waitForExistence(timeout: 2))
        answer.tap()
        XCTAssertTrue(
            app.staticTexts["reality.reflection-confirmation"]
                .waitForExistence(timeout: 1)
        )
    }

    @MainActor
    func testDevelopingStageDoesNotExposeProgressIndicator() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "generating"
        app.launch()

        XCTAssertTrue(app.otherElements["reality.developing-stage"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.progressIndicators.firstMatch.exists)
    }

    @MainActor
    func testDevelopingStageDoesNotShowTopCoverControl() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "understanding"
        app.launch()

        XCTAssertTrue(app.otherElements["hero.hand-photo"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["reality.darkroom-control"].exists)
        XCTAssertFalse(app.staticTexts["遮住顶部"].exists)
        XCTAssertFalse(app.staticTexts["TIME DARKROOM"].exists)
    }

    @MainActor
    func testPresentTimeReflectionUsesAWrittenNote() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "generating"
        app.launchEnvironment["FUMIRA_AUDIT_TARGET_TIME"] = "now"
        app.launch()

        let photo = app.otherElements["hero.hand-photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3))
        let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        let end = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        start.press(forDuration: 0.12, thenDragTo: end)

        let note = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", "写给未来的这里…")
        ).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        note.tap()
        note.typeText("给未来的一句问候")
        let save = app.buttons["reality.reflection-save-note"]
        XCTAssertTrue(save.waitForExistence(timeout: 1))
        save.tap()
        XCTAssertTrue(
            app.staticTexts["reality.reflection-confirmation"]
                .waitForExistence(timeout: 1)
        )
    }

    @MainActor
    func testHorizontalInspectionRevealsMicroTimeSlice() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "understanding"
        app.launch()

        let stage = app.otherElements["reality.developing-stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 3))

        // The photo owns horizontal turns and the new darkroom owns the lower
        // shelf. Start in the leading canvas margin so this remains the stage's
        // separate temporal-slice scrub rather than either child interaction.
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.50))
        let end = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.50))
        start.press(forDuration: 0.08, thenDragTo: end)

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

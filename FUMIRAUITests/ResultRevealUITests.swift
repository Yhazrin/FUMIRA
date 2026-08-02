import XCTest

final class ResultRevealUITests: XCTestCase {
    @MainActor
    func testResultPageKeepsHeroAndActionsInDocumentFlow() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "result"
        app.launchEnvironment["FUMIRA_AUDIT_RESULT_REVEAL"] = "1"
        app.launch()

        let hero = app.otherElements["hero.photo"]
        let actionDock = app.otherElements["result.action-dock"]
        XCTAssertTrue(hero.waitForExistence(timeout: 3))
        XCTAssertTrue(actionDock.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            actionDock.frame.minY,
            hero.frame.maxY - 1,
            "结果操作不应覆盖生成照片"
        )
        XCTAssertFalse(app.buttons["设置"].exists, "结果页不应再叠加根级设置齿轮")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "result-document-flow"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testButtonFallbackCompletesBlowReveal() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "result"
        app.launchEnvironment["FUMIRA_EXPERIMENTS"] = "blowReveal"
        app.launch()

        let revealButton = app.buttons["result.reveal-now"]
        XCTAssertTrue(revealButton.waitForExistence(timeout: 3))
        revealButton.tap()

        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: revealButton)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testBlowRevealUsesOnePhysicalSurfaceAtPartialProgress() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "result"
        app.launchEnvironment["FUMIRA_EXPERIMENTS"] = "blowReveal"
        app.launchEnvironment["FUMIRA_AUDIT_RESULT_REVEAL_PROGRESS"] = "0.56"
        app.launchEnvironment["FUMIRA_AUDIT_BLOW_GUST"] = "0.88"
        app.launch()

        let surface = app.images["result.blow-reveal"]
        XCTAssertTrue(surface.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["吹一口气"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '转动'")).firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "result-blow-reveal-partial"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

        let modeButton = app.buttons["result.comparison-mode"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 2))
        modeButton.tap()

        let holdButton = app.buttons["result.blink-hold"]
        XCTAssertTrue(holdButton.waitForExistence(timeout: 2))
        let cadenceButton = app.buttons["result.blink-cadence"]
        XCTAssertTrue(cadenceButton.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(cadenceButton.frame.height, 44)

        modeButton.tap()
        XCTAssertTrue(boundary.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["关闭现实对照"].exists)
    }

    @MainActor
    func testBrowsedTimeRequiresExplicitGenerationAndExposesTiltTime() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "result"
        app.launchEnvironment["FUMIRA_AUDIT_RESULT_REVEAL"] = "1"
        app.launchEnvironment["FUMIRA_AUDIT_BROWSE_TIME"] = "past"
        app.launch()

        let generateButton = app.buttons["result.generate-browsed-frame"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["8.5 年后的回信"].exists)

        let tiltButton = app.buttons["result.tilt-time"]
        XCTAssertTrue(tiltButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(tiltButton.frame.height, 44)
        if !tiltButton.isHittable {
            app.swipeUp()
        }
        tiltButton.tap()
        XCTAssertEqual(tiltButton.label, "停止倾斜穿越")

        if !generateButton.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(generateButton.isHittable)
        generateButton.tap()
        XCTAssertTrue(app.staticTexts["46 年前的回信"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["result.generate-browsed-frame"].exists)
    }

    @MainActor
    func testFutureForkFallbackChangesPossibilityWithoutChangingExactTime() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "result"
        app.launchEnvironment["FUMIRA_AUDIT_RESULT_REVEAL"] = "1"
        app.launchEnvironment["FUMIRA_AUDIT_TARGET_TIME"] = "future"
        app.launchEnvironment["FUMIRA_EXPERIMENTS"] = "futureFork,shakeToFork"
        app.launch()

        let header = app.otherElements["result.future-fork"]
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["8.5 年后的回信"].exists)

        let advance = app.buttons["result.future-fork.advance"]
        if !advance.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(advance.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(advance.frame.height, 44)
        advance.tap()

        let secondBranch = app.buttons["result.future-fork.branch.1"]
        let selected = NSPredicate(format: "value == %@", "当前分支")
        expectation(for: selected, evaluatedWith: secondBranch)
        waitForExpectations(timeout: 2)

        XCTAssertTrue(app.staticTexts["8.5 年后的回信"].exists)
        let generate = app.buttons["result.future-fork.generate"]
        XCTAssertTrue(generate.exists)
        XCTAssertGreaterThanOrEqual(generate.frame.height, 44)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "future-fork-result"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

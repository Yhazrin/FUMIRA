import XCTest

/// Repeatable simulator evidence for the two transition paths most likely to
/// regress into main-thread stalls. These metrics are diagnostic rather than
/// hard performance baselines because simulator load varies across hosts.
@available(iOS 26.0, *)
final class PerformanceFlowUITests: XCTestCase {
    @MainActor
    func testCameraEntryTransitionPerformance() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("UI hitch metrics require iOS 26 or newer")
        }

        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "connection"
        app.launchEnvironment["FUMIRA_AUDIT_AUTO_CAMERA_GRANT"] = "1"

        measureTransition(application: app) {
            let source = app.buttons["进入时间相机"]
            XCTAssertTrue(source.waitForExistence(timeout: 3))
        } performTransition: {
            app.buttons["进入时间相机"].tap()
        } waitForDestination: {
            XCTAssertTrue(
                app.otherElements["viewfinder.aspect-control"]
                    .waitForExistence(timeout: 3)
            )
        }
    }

    @MainActor
    func testPhotoFlipLandingPerformance() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("UI hitch metrics require iOS 26 or newer")
        }

        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "shuttered"
        app.launchEnvironment["FUMIRA_AUDIT_TRANSITION"] = "capture"
        // Leave enough time for XCUIApplication.launch() to return before the
        // debug transition begins, so the measured interval includes the flip.
        app.launchEnvironment["FUMIRA_AUDIT_DELAY_MS"] = "2500"

        measureTransition(application: app) {
            XCTAssertTrue(
                app.otherElements["hero.photo"]
                    .waitForExistence(timeout: 3)
            )
        } performTransition: {
        } waitForDestination: {
            XCTAssertTrue(
                app.otherElements["reality.developing-stage"]
                    .waitForExistence(timeout: 3)
            )
        }
    }

    @MainActor
    private func measureTransition(
        application: XCUIApplication,
        waitForSource: () -> Void,
        performTransition: () -> Void,
        waitForDestination: () -> Void
    ) {
        let options = XCTMeasureOptions()
        options.iterationCount = 2
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(
            metrics: [
                XCTHitchMetric(application: application),
                XCTCPUMetric(application: application),
                XCTMemoryMetric(application: application),
                XCTClockMetric(),
            ],
            options: options
        ) {
            application.terminate()
            application.launch()
            waitForSource()
            startMeasuring()
            performTransition()
            waitForDestination()
            stopMeasuring()
        }
    }
}

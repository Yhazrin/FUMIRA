import XCTest

final class SettingsUITests: XCTestCase {
    @MainActor
    func testSettingsListPresentsInteractiveContent() {
        let app = XCUIApplication()
        app.launchEnvironment["FUMIRA_AUDIT_PHASE"] = "cameraPermission"
        app.launchEnvironment["FUMIRA_AUDIT_SETTINGS"] = "1"
        app.launch()

        let gridToggle = app.switches["取景网格"]
        XCTAssertTrue(gridToggle.waitForExistence(timeout: 3))
        XCTAssertTrue(gridToggle.isHittable)
    }
}

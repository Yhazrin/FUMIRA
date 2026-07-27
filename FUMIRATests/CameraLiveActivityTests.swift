import Foundation
import XCTest
@testable import FUMIRA

@MainActor
final class CameraLiveActivityTests: XCTestCase {
    func testContentStateRoundTripsThroughActivityKitPayloadEncoding() throws {
        let state = CameraLiveActivityAttributes.ContentState(
            phase: .framing,
            targetLabel: "NOW",
            zoomLabel: "1.0×",
            flashSymbol: "bolt.badge.automatic.fill",
            lensSymbol: "arrow.triangle.2.circlepath",
            isGridEnabled: true,
            aspectRatioLabel: "3:4"
        )

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            CameraLiveActivityAttributes.ContentState.self,
            from: encoded
        )

        XCTAssertEqual(decoded, state)
    }

    func testDynamicIslandCameraLinksReachViewfinderActions() {
        let model = AppModel(dependencies: .test)
        model.phase = .viewfinder

        model.handleDeepLink(URL(string: "fumira://camera/grid")!)
        XCTAssertTrue(model.isCameraGridEnabled)

        XCTAssertEqual(model.cameraAspectRatio, .classic)
        model.handleDeepLink(URL(string: "fumira://camera/aspect")!)
        XCTAssertEqual(model.cameraAspectRatio, .square)
    }
}

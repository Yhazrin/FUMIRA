import XCTest
import SwiftUI
import UIKit
@testable import FUMIRA

final class CameraControlTests: XCTestCase {
    @MainActor
    func testDoraemonCameraChromeStaysOpaqueAndLegible() throws {
        let action = try rgba(PosterEffects.cameraActionFill)
        let actionGlyph = try rgba(PosterEffects.cameraActionForeground)
        let compactFeedback = try rgba(PosterEffects.cameraChromeSolidFill)
        let compactText = try rgba(PosterEffects.cameraChromeSolidForeground)

        XCTAssertEqual(action.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(compactFeedback.alpha, 1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            contrastRatio(action, actionGlyph),
            2.45,
            "Warm-white glyphs need non-text contrast against the orange action circle"
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio(compactFeedback, compactText),
            4.1,
            "Warm-white status text needs AA contrast against the orange-rim card"
        )
    }

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

    func testZoomClampsToRecommendedHardwareRange() {
        let snapshot = CameraZoomSnapshot(
            factor: 2,
            displayFactor: 1,
            minimumFactor: 1,
            maximumFactor: 8
        )

        XCTAssertEqual(snapshot.clamping(0.5).factor, 1)
        XCTAssertEqual(snapshot.clamping(12).factor, 8)
        XCTAssertEqual(snapshot.clamping(4).factor, 4)
    }

    func testZoomClampingPreservesDisplayMultiplier() {
        let snapshot = CameraZoomSnapshot(
            factor: 2,
            displayFactor: 1,
            minimumFactor: 1,
            maximumFactor: 8
        )

        XCTAssertEqual(snapshot.clamping(6).displayFactor, 3)
    }

    func testUnavailableZoomHasNoAdjustableRange() {
        XCTAssertFalse(CameraZoomSnapshot.unavailable.isAvailable)
    }

    func testPinchMapsFromTheRatioHeldAtGestureStart() {
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterPinchMagnification: 1.18,
                startingAt: .classic
            ),
            .widescreen
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterPinchMagnification: 0.84,
                startingAt: .classic
            ),
            .square
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterPinchMagnification: 0.58,
                startingAt: .classic
            ),
            .square
        )
    }

    func testVerticalDragMapsFromTheRatioHeldAtGestureStart() {
        let step = CameraAspectRatio.verticalAspectStepDistance
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterVerticalTranslation: step * 1.2,
                startingAt: .classic
            ),
            .widescreen
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterVerticalTranslation: -step * 1.2,
                startingAt: .classic
            ),
            .square
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterVerticalTranslation: step * 2.4,
                startingAt: .classic
            ),
            .fullScreen
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterVerticalTranslation: step * 0.4,
                startingAt: .classic
            ),
            .classic
        )
    }

    func testPinchAspectMappingClampsAndRejectsInvalidMagnification() {
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterPinchMagnification: 4,
                startingAt: .square
            ),
            .fullScreen
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterPinchMagnification: 0.1,
                startingAt: .fullScreen
            ),
            .square
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterPinchMagnification: .nan,
                startingAt: .classic
            ),
            .classic
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterVerticalTranslation: .nan,
                startingAt: .classic
            ),
            .classic
        )
        XCTAssertEqual(
            CameraAspectRatio.aspectRatio(
                afterVerticalTranslation: 10_000,
                startingAt: .square
            ),
            .fullScreen
        )
    }

    func testMockCaptureKeepsHighDensityPixelsAcrossVisibleCompositions() async throws {
        let camera = MockCameraService()

        let classic = try await camera.capturePhoto(composition: .classic)
        let widescreen = try await camera.capturePhoto(composition: .widescreen)
        let square = try await camera.capturePhoto(composition: .square)

        XCTAssertGreaterThanOrEqual(classic.pixelHeight, 1_500)
        XCTAssertEqual(
            Double(classic.pixelWidth) / Double(classic.pixelHeight),
            3.0 / 4.0,
            accuracy: 0.02
        )
        XCTAssertGreaterThanOrEqual(widescreen.pixelHeight, 1_500)
        XCTAssertEqual(
            Double(widescreen.pixelWidth) / Double(widescreen.pixelHeight),
            9.0 / 16.0,
            accuracy: 0.02
        )
        XCTAssertGreaterThanOrEqual(square.pixelWidth, 1_100)
        XCTAssertEqual(square.pixelWidth, square.pixelHeight)
        XCTAssertFalse(classic.data.isEmpty)
        XCTAssertFalse(widescreen.data.isEmpty)
        XCTAssertFalse(square.data.isEmpty)
    }

    @MainActor
    private func rgba(_ color: Color) throws -> RGBA {
        let resolved = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            throw XCTSkip("Camera chrome color could not be resolved in the light appearance")
        }
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func contrastRatio(_ lhs: RGBA, _ rhs: RGBA) -> CGFloat {
        let brighter = max(lhs.relativeLuminance, rhs.relativeLuminance)
        let darker = min(lhs.relativeLuminance, rhs.relativeLuminance)
        return (brighter + 0.05) / (darker + 0.05)
    }
}

private struct RGBA {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    var relativeLuminance: CGFloat {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func linear(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

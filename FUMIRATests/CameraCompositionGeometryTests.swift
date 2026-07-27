import XCTest
@testable import FUMIRA

final class CameraCompositionGeometryTests: XCTestCase {
    func testClassicCropIsCenteredAndContainedAcrossPhoneSizes() throws {
        let phoneSizes = [
            CGSize(width: 320, height: 568),
            CGSize(width: 393, height: 852),
            CGSize(width: 402, height: 874),
            CGSize(width: 430, height: 932),
        ]

        for size in phoneSizes {
            let layout = CameraCompositionGeometry.layout(
                aspectRatio: .classic,
                in: size
            )
            let crop = try XCTUnwrap(layout.cropFrame)

            XCTAssertEqual(crop.midX, size.width / 2, accuracy: 0.001)
            XCTAssertEqual(crop.width / crop.height, 3.0 / 4.0, accuracy: 0.001)
            assertContains(crop, in: layout.viewport)
            XCTAssertEqual(layout.heroFrame, crop)
        }
    }

    func testEveryCropRatioUsesOneCenteredFrame() throws {
        let size = CGSize(width: 402, height: 874)

        for aspectRatio in [CameraAspectRatio.widescreen, .classic, .square] {
            let layout = CameraCompositionGeometry.layout(
                aspectRatio: aspectRatio,
                in: size
            )
            let crop = try XCTUnwrap(layout.cropFrame)
            let expectedRatio = try XCTUnwrap(aspectRatio.targetAspectRatio(for: size))

            XCTAssertEqual(crop.midX, size.width / 2, accuracy: 0.001)
            XCTAssertEqual(crop.width / crop.height, expectedRatio, accuracy: 0.001)
            XCTAssertGreaterThan(crop.width, 0)
            XCTAssertGreaterThan(crop.height, 0)
            assertContains(crop, in: layout.viewport)
        }
    }

    func testFullScreenUsesContainerWithoutCompositionHole() {
        let size = CGSize(width: 402, height: 874)
        let layout = CameraCompositionGeometry.layout(
            aspectRatio: .fullScreen,
            in: size
        )

        XCTAssertNil(layout.cropFrame)
        XCTAssertEqual(layout.heroFrame, CGRect(origin: .zero, size: size))
        XCTAssertEqual(layout.viewport, layout.heroFrame)
        XCTAssertEqual(layout.cornerRadius, 0)
    }

    func testLandscapeRatiosFollowPhysicalOrientation() throws {
        let size = CGSize(width: 874, height: 402)

        let classic = try XCTUnwrap(
            CameraCompositionGeometry.layout(aspectRatio: .classic, in: size).cropFrame
        )
        let widescreen = try XCTUnwrap(
            CameraCompositionGeometry.layout(aspectRatio: .widescreen, in: size).cropFrame
        )

        XCTAssertEqual(classic.width / classic.height, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(widescreen.width / widescreen.height, 16.0 / 9.0, accuracy: 0.001)
    }

    func testUnderstandingPaperLandsBelowViewfinderCenterAndStaysContained() {
        let phoneSizes = [
            CGSize(width: 320, height: 568),
            CGSize(width: 393, height: 852),
            CGSize(width: 430, height: 932),
        ]

        for size in phoneSizes {
            let frame = HeroPhotoMetrics.understandingFrame(
                aspectRatio: 3.0 / 4.0,
                in: size
            )

            XCTAssertEqual(frame.midX, size.width / 2, accuracy: 0.001)
            XCTAssertGreaterThan(frame.midY, size.height / 2)
            XCTAssertEqual(frame.width / frame.height, 3.0 / 4.0, accuracy: 0.001)
            assertContains(frame, in: CGRect(origin: .zero, size: size))
        }
    }

    private func assertContains(
        _ inner: CGRect,
        in outer: CGRect,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(inner.minX, outer.minX - accuracy, file: file, line: line)
        XCTAssertGreaterThanOrEqual(inner.minY, outer.minY - accuracy, file: file, line: line)
        XCTAssertLessThanOrEqual(inner.maxX, outer.maxX + accuracy, file: file, line: line)
        XCTAssertLessThanOrEqual(inner.maxY, outer.maxY + accuracy, file: file, line: line)
    }
}

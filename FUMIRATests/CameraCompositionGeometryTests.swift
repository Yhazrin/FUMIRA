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

    func testFullScreenOccupiesTheEntireStageWithoutCardCorners() {
        let size = CGSize(width: 402, height: 874)
        let layout = CameraCompositionGeometry.layout(
            aspectRatio: .fullScreen,
            in: size
        )

        XCTAssertNil(layout.cropFrame)
        XCTAssertEqual(layout.heroFrame, layout.viewport)
        XCTAssertEqual(layout.viewport, layout.heroFrame)
        XCTAssertEqual(layout.heroFrame.minX, 0)
        XCTAssertEqual(layout.heroFrame.minY, 0)
        XCTAssertEqual(layout.heroFrame.width, size.width)
        XCTAssertEqual(layout.heroFrame.height, size.height)
        XCTAssertEqual(layout.heroFrame.maxY, size.height)
        XCTAssertEqual(layout.cornerRadius, 0)
    }

    func testModernPortraitRatiosUseTheFullScreenWidth() throws {
        let size = CGSize(width: 393, height: 852)

        for aspectRatio in [CameraAspectRatio.widescreen, .classic, .square] {
            let frame = try XCTUnwrap(
                CameraCompositionGeometry.layout(
                    aspectRatio: aspectRatio,
                    in: size
                ).cropFrame
            )

            XCTAssertEqual(frame.minX, 0, accuracy: 0.001)
            XCTAssertEqual(frame.width, size.width, accuracy: 0.001)
        }
    }

    func testAspectCardsShareTopEdgeAndExposeMoreBodyAsTheyShorten() throws {
        let size = CGSize(width: 402, height: 874)
        let fullScreen = CameraCompositionGeometry.layout(
            aspectRatio: .fullScreen,
            in: size
        )
        let classic = try XCTUnwrap(
            CameraCompositionGeometry.layout(aspectRatio: .classic, in: size).cropFrame
        )
        let square = try XCTUnwrap(
            CameraCompositionGeometry.layout(aspectRatio: .square, in: size).cropFrame
        )
        let widescreen = try XCTUnwrap(
            CameraCompositionGeometry.layout(aspectRatio: .widescreen, in: size).cropFrame
        )

        XCTAssertEqual(classic.minY, fullScreen.heroFrame.minY, accuracy: 0.001)
        XCTAssertEqual(square.minY, fullScreen.heroFrame.minY, accuracy: 0.001)
        XCTAssertEqual(widescreen.minY, fullScreen.heroFrame.minY, accuracy: 0.001)
        XCTAssertLessThan(widescreen.maxY, fullScreen.heroFrame.maxY)
        XCTAssertLessThan(classic.maxY, fullScreen.heroFrame.maxY)
        XCTAssertLessThan(square.maxY, classic.maxY)
        XCTAssertGreaterThan(size.height - square.maxY, size.height - classic.maxY)
    }

    func testWaveShutterTracksTheOpticalCenterOfEachExposedDeck() {
        let size = CGSize(width: 393, height: 852)
        let bottomSafeArea: CGFloat = 34
        let classic = CameraCompositionGeometry.layout(
            aspectRatio: .classic,
            in: size
        ).heroFrame
        let square = CameraCompositionGeometry.layout(
            aspectRatio: .square,
            in: size
        ).heroFrame
        let classicCenter = CameraCompositionGeometry.controlDeckCenterY(
            below: classic,
            in: size,
            bottomSafeAreaInset: bottomSafeArea
        )
        let squareCenter = CameraCompositionGeometry.controlDeckCenterY(
            below: square,
            in: size,
            bottomSafeAreaInset: bottomSafeArea
        )

        XCTAssertGreaterThan(classicCenter, classic.maxY)
        XCTAssertGreaterThan(squareCenter, square.maxY)
        XCTAssertLessThan(classicCenter, size.height - bottomSafeArea)
        XCTAssertLessThan(squareCenter, classicCenter)
    }

    func testWaveShutterFloatsForFullScreenAndShallowDecks() throws {
        let size = CGSize(width: 393, height: 852)
        let bottomSafeArea: CGFloat = 34
        let fullScreen = CameraCompositionGeometry.layout(
            aspectRatio: .fullScreen,
            in: size
        ).heroFrame
        let widescreen = try XCTUnwrap(
            CameraCompositionGeometry.layout(
                aspectRatio: .widescreen,
                in: size
            ).cropFrame
        )
        let classic = try XCTUnwrap(
            CameraCompositionGeometry.layout(
                aspectRatio: .classic,
                in: size
            ).cropFrame
        )
        let square = try XCTUnwrap(
            CameraCompositionGeometry.layout(
                aspectRatio: .square,
                in: size
            ).cropFrame
        )
        let fullPlacement = CameraCompositionGeometry.controlPlacement(
            below: fullScreen,
            in: size,
            bottomSafeAreaInset: bottomSafeArea
        )
        let widescreenPlacement = CameraCompositionGeometry.controlPlacement(
            below: widescreen,
            in: size,
            bottomSafeAreaInset: bottomSafeArea
        )
        let classicPlacement = CameraCompositionGeometry.controlPlacement(
            below: classic,
            in: size,
            bottomSafeAreaInset: bottomSafeArea
        )
        let squarePlacement = CameraCompositionGeometry.controlPlacement(
            below: square,
            in: size,
            bottomSafeAreaInset: bottomSafeArea
        )

        XCTAssertTrue(fullPlacement.overlaysPreview)
        // Portrait 16:9 still exposes a usable blue deck — center there, do
        // not float over the preview the way full screen must.
        XCTAssertFalse(widescreenPlacement.overlaysPreview)
        XCTAssertFalse(classicPlacement.overlaysPreview)
        XCTAssertFalse(squarePlacement.overlaysPreview)
        XCTAssertLessThan(fullPlacement.centerY, fullScreen.maxY)
        XCTAssertGreaterThan(widescreenPlacement.centerY, widescreen.maxY)
        // Deeper blue decks lift the optical center; shallow 16:9 sits lower.
        XCTAssertLessThan(squarePlacement.centerY, classicPlacement.centerY)
        XCTAssertLessThan(classicPlacement.centerY, widescreenPlacement.centerY)

        let opticalBias =
            CameraChromeMetrics.waveRailHeight * 0.5
            - CameraChromeMetrics.waveRailStageHeight * 0.58
        let expectedWidescreenCenter = min(
            max(
                (widescreen.maxY + size.height) * 0.5 + opticalBias,
                widescreen.maxY + CameraChromeMetrics.waveRailHeight * 0.5
            ),
            size.height - CameraChromeMetrics.waveRailHeight * 0.5
        )
        XCTAssertEqual(
            widescreenPlacement.centerY,
            expectedWidescreenCenter,
            accuracy: 0.001
        )

        let expectedClassicCenter =
            (classic.maxY + size.height) * 0.5 + opticalBias
        XCTAssertEqual(
            classicPlacement.centerY,
            expectedClassicCenter,
            accuracy: 0.001
        )
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

    func testHeroSlotInterpolationPreservesEndpointsAndClampsProgress() {
        let source = HeroSlotPreference(
            frame: CGRect(x: 0, y: 20, width: 400, height: 700),
            cornerRadius: 0
        )
        let destination = HeroSlotPreference(
            frame: CGRect(x: 60, y: 160, width: 280, height: 360),
            cornerRadius: 24
        )

        XCTAssertEqual(source.interpolated(to: destination, progress: -1), source)
        XCTAssertEqual(source.interpolated(to: destination, progress: 2), destination)

        let midpoint = source.interpolated(to: destination, progress: 0.5)
        XCTAssertEqual(midpoint.frame, CGRect(x: 30, y: 90, width: 340, height: 530))
        XCTAssertEqual(midpoint.cornerRadius, 12)
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

import XCTest
import UIKit
@testable import FUMIRA

final class PhotoImportAdapterTests: XCTestCase {
    func testClassicCompositionFollowsLandscapeOrientation() throws {
        let source = makeJPEG(width: 1_600, height: 900, color: .systemBlue)
        let photo = try PhotoImportAdapter.makeCapturedPhoto(from: source)

        XCTAssertGreaterThan(photo.pixelWidth, 0)
        XCTAssertGreaterThan(photo.pixelHeight, 0)
        let ratio = Double(photo.pixelWidth) / Double(photo.pixelHeight)
        XCTAssertEqual(ratio, 4.0 / 3.0, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
    }

    func testAlreadyThreeByFourKeepsDecodableJPEG() throws {
        let source = makeJPEG(width: 900, height: 1_200, color: .systemGreen)
        let photo = try PhotoImportAdapter.makeCapturedPhoto(from: source)

        XCTAssertEqual(Double(photo.pixelWidth) / Double(photo.pixelHeight), 0.75, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
    }

    func testWideCompositionFollowsLandscapeOrientation() throws {
        let source = makeJPEG(width: 1_200, height: 900, color: .systemOrange)
        let photo = try PhotoImportAdapter.makeCapturedPhoto(from: source, composition: .widescreen)

        XCTAssertEqual(Double(photo.pixelWidth) / Double(photo.pixelHeight), 16.0 / 9.0, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
    }

    func testSquareCompositionProducesSquarePhoto() throws {
        let source = makeJPEG(width: 1_200, height: 1_600, color: .systemPurple)
        let photo = try PhotoImportAdapter.makeCapturedPhoto(from: source, composition: .square)

        XCTAssertEqual(Double(photo.pixelWidth) / Double(photo.pixelHeight), 1, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
    }

    func testCapturedPhotoExposesItsNormalisedDisplayAspectRatio() throws {
        let portrait = CapturedPhoto(data: Data(), pixelWidth: 900, pixelHeight: 1_600)
        let landscape = CapturedPhoto(data: Data(), pixelWidth: 1_600, pixelHeight: 900)
        let unknown = CapturedPhoto(data: Data())

        XCTAssertEqual(
            try XCTUnwrap(portrait.displayAspectRatio),
            9.0 / 16.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(landscape.displayAspectRatio),
            16.0 / 9.0,
            accuracy: 0.0001
        )
        XCTAssertNil(unknown.displayAspectRatio)
    }

    func testInvalidDataThrows() {
        XCTAssertThrowsError(try PhotoImportAdapter.makeCapturedPhoto(from: Data([0x00, 0x01]))) { error in
            XCTAssertTrue(error is PhotoImportAdapter.ImportError)
        }
    }

    private func makeJPEG(width: Int, height: Int, color: UIColor) -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

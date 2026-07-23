import XCTest
import UIKit
@testable import FUMIRA

final class PhotoImportAdapterTests: XCTestCase {
    func testCenterCropProducesPortraitThreeByFour() throws {
        let source = makeJPEG(width: 1_600, height: 900, color: .systemBlue)
        let photo = try PhotoImportAdapter.makeCapturedPhoto(from: source)

        XCTAssertGreaterThan(photo.pixelWidth, 0)
        XCTAssertGreaterThan(photo.pixelHeight, 0)
        let ratio = Double(photo.pixelWidth) / Double(photo.pixelHeight)
        XCTAssertEqual(ratio, 0.75, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
    }

    func testAlreadyThreeByFourKeepsDecodableJPEG() throws {
        let source = makeJPEG(width: 900, height: 1_200, color: .systemGreen)
        let photo = try PhotoImportAdapter.makeCapturedPhoto(from: source)

        XCTAssertEqual(Double(photo.pixelWidth) / Double(photo.pixelHeight), 0.75, accuracy: 0.02)
        XCTAssertNotNil(UIImage(data: photo.data))
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

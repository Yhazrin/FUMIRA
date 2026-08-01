import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FUMIRA

final class MockGenerationProviderTests: XCTestCase {
    func testPastNowAndFutureProduceVisiblyDistinctImages() async throws {
        let provider = MockGenerationProvider(stepDelay: .zero)
        let photo = CapturedPhoto(data: try makeSourceJPEG())

        let past = try await generatedData(
            from: provider,
            photo: photo,
            time: TimePosition(normalized: -0.8)
        )
        let now = try await generatedData(
            from: provider,
            photo: photo,
            time: .now
        )
        let future = try await generatedData(
            from: provider,
            photo: photo,
            time: TimePosition(normalized: 0.8)
        )

        XCTAssertNotEqual(past, now)
        XCTAssertNotEqual(now, future)
        XCTAssertNotEqual(past, future)
        XCTAssertGreaterThan(colorDistance(try averageColor(in: past), try averageColor(in: now)), 12)
        XCTAssertGreaterThan(colorDistance(try averageColor(in: now), try averageColor(in: future)), 12)
        XCTAssertGreaterThan(colorDistance(try averageColor(in: past), try averageColor(in: future)), 20)
    }

    func testSameInputAndTimeAreStableAcrossSessionsAndProviders() async throws {
        let photo = CapturedPhoto(data: try makeSourceJPEG())
        let time = TimePosition(normalized: 0.57)

        let first = try await generatedData(
            from: MockGenerationProvider(stepDelay: .zero),
            photo: photo,
            time: time,
            sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let second = try await generatedData(
            from: MockGenerationProvider(stepDelay: .zero),
            photo: photo,
            time: time,
            sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )

        XCTAssertEqual(first, second)
    }

    func testTemporalRenderingKeepsSourceSubjectReadable() async throws {
        let provider = MockGenerationProvider(stepDelay: .zero)
        let photo = CapturedPhoto(data: try makeSourceJPEG())

        for time in [
            TimePosition(normalized: -1),
            TimePosition.now,
            TimePosition(normalized: 1),
        ] {
            let data = try await generatedData(from: provider, photo: photo, time: time)
            let image = try decodedImage(from: data)
            let center = try pixelColor(in: image, x: image.width / 2, y: image.height / 2)
            let background = try pixelColor(in: image, x: 8, y: 8)

            XCTAssertEqual(image.width, 160)
            XCTAssertEqual(image.height, 120)
            XCTAssertGreaterThan(
                colorDistance(center, background),
                70,
                "The bright central subject must remain distinct from its background"
            )
        }
    }

    private func generatedData(
        from provider: MockGenerationProvider,
        photo: CapturedPhoto,
        time: TimePosition,
        sessionID: UUID = UUID()
    ) async throws -> Data {
        let model = try XCTUnwrap(
            AIModelCatalog.bundled.option(id: AIModelConfiguration.standard.imageOptionID)
        )
        let request = ImageGenerationRequest(
            photo: photo,
            time: time,
            prompt: "mock-test",
            sessionID: sessionID,
            model: model
        )
        let stream = await provider.generate(request: request)
        for try await event in stream {
            if case let .completed(frame) = event {
                return try XCTUnwrap(frame.imageData)
            }
        }
        XCTFail("Mock generation finished without a completed frame")
        throw TestError.missingFrame
    }

    private func makeSourceJPEG() throws -> Data {
        let width = 160
        let height = 120
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        context.setFillColor(red: 0.08, green: 0.12, blue: 0.16, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(red: 0.92, green: 0.72, blue: 0.18, alpha: 1)
        context.fill(CGRect(x: 52, y: 30, width: 56, height: 68))
        context.setFillColor(red: 0.16, green: 0.72, blue: 0.34, alpha: 1)
        context.fill(CGRect(x: 72, y: 52, width: 16, height: 24))

        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func decodedImage(from data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func averageColor(in data: Data) throws -> RGBA {
        let image = try decodedImage(from: data)
        return try pixelColor(in: image, x: image.width / 2, y: image.height / 2)
    }

    private func pixelColor(in image: CGImage, x: Int, y: Int) throws -> RGBA {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let madeContext = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(image.width),
                    height: CGFloat(image.height)
                )
            )
            return true
        }
        guard madeContext else { throw TestError.pixelContext }
        return RGBA(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes[3])
    }

    private func colorDistance(_ lhs: RGBA, _ rhs: RGBA) -> Double {
        let red = Double(lhs.red) - Double(rhs.red)
        let green = Double(lhs.green) - Double(rhs.green)
        let blue = Double(lhs.blue) - Double(rhs.blue)
        return sqrt(red * red + green * green + blue * blue)
    }
}

private struct RGBA {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private enum TestError: Error {
    case missingFrame
    case pixelContext
}

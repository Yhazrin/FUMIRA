import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Produces a bounded JPEG payload for the FUMIRA relay.
///
/// `AVCapturePhoto.fileDataRepresentation()` may be HEIC on a real device even
/// when the caller labels it as JPEG. Normalising here makes the multipart
/// content type truthful and keeps the request safely below the relay limit.
enum UploadImageEncoder {
    static let maximumBytes = 9 * 1_024 * 1_024

    static func jpegData(from original: Data) throws -> Data {
        guard
            let source = CGImageSourceCreateWithData(original as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else {
            throw EncodingError.invalidImage
        }

        for maximumPixel in [3_072, 2_560, 2_048] {
            guard let image = thumbnail(from: source, maximumPixel: maximumPixel) else {
                continue
            }
            for quality in [0.90, 0.82, 0.74, 0.66] {
                let encoded = encodeJPEG(image, quality: quality)
                if encoded.count <= maximumBytes {
                    return encoded
                }
            }
        }

        throw EncodingError.tooLarge
    }

    private static func thumbnail(
        from source: CGImageSource,
        maximumPixel: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return output as Data
    }

    enum EncodingError: Error {
        case invalidImage
        case tooLarge
    }
}

import Foundation
import UIKit

/// Normalises album and live-camera bytes into the composition selected in the
/// viewfinder. Cropping remains deliberately silent: the live guide is the
/// contract, rather than a separate editing screen.
enum PhotoImportAdapter {
    /// Match mock camera long edge for predictable downstream payloads.
    static let maxLongEdge: CGFloat = 1_600
    static let jpegQuality: CGFloat = 0.92

    enum ImportError: LocalizedError {
        case invalidImage
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                "无法读取这张照片，请换一张再试。"
            case .encodingFailed:
                "照片处理失败，请换一张再试。"
            }
        }
    }

    static func makeCapturedPhoto(
        from original: Data,
        composition: CameraAspectRatio = .classic
    ) throws -> CapturedPhoto {
        guard let image = UIImage(data: original) else {
            throw ImportError.invalidImage
        }
        let oriented = image.normalizedUpOrientation()
        let cropped: UIImage
        if let targetRatio = composition.targetAspectRatio(for: oriented.size) {
            cropped = centerCrop(oriented, targetRatio: targetRatio)
        } else {
            cropped = oriented
        }
        let scaled = fitLongEdge(cropped, maxLongEdge: maxLongEdge)
        guard let jpeg = scaled.jpegData(compressionQuality: jpegQuality) else {
            throw ImportError.encodingFailed
        }
        let width = Int((scaled.size.width * scaled.scale).rounded())
        let height = Int((scaled.size.height * scaled.scale).rounded())
        return CapturedPhoto(data: jpeg, pixelWidth: width, pixelHeight: height)
    }

    /// Center-crop to the requested width / height ratio.
    static func centerCrop(
        _ image: UIImage,
        targetRatio: CGFloat
    ) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let imageRatio = size.width / size.height

        let cropRect: CGRect
        if imageRatio > targetRatio {
            let width = size.height * targetRatio
            cropRect = CGRect(
                x: (size.width - width) / 2,
                y: 0,
                width: width,
                height: size.height
            )
        } else if imageRatio < targetRatio {
            let height = size.width / targetRatio
            cropRect = CGRect(
                x: 0,
                y: (size.height - height) / 2,
                width: size.width,
                height: height
            )
        } else {
            return image
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
        return renderer.image { _ in
            image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
    }

    static func fitLongEdge(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }
        let scale = maxLongEdge / longEdge
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private extension UIImage {
    /// Bakes EXIF orientation into pixel buffers so crop math uses upright geometry.
    func normalizedUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

import CoreImage
import Foundation
import ImageIO
import Vision

actor VisionSceneLayerAnalyzer: SceneLayerAnalyzing {
    func analyze(photo: CapturedPhoto) async -> TemporalVisualContext {
        let data = photo.data
        return await Task.detached(priority: .userInitiated) {
            Self.analyze(data: data)
        }.value
    }

    private nonisolated static func analyze(data: Data) -> TemporalVisualContext {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return .unavailable
        }

        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .balanced
        person.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try? handler.perform([foreground, person, saliency])

        let foregroundBuffer = foreground.results?.first.flatMap { observation in
            try? observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
        }
        let personBuffer = person.results?.first?.pixelBuffer
        let mask = (foregroundBuffer ?? personBuffer)
            .flatMap(encodedAlphaMask(from:))
        let regions: [TemporalSalientRegion]
        if let objects = saliency.results?.first?.salientObjects {
            regions = objects.prefix(3).map { observation in
                let box = observation.boundingBox
                return TemporalSalientRegion(
                    normalizedX: box.minX,
                    normalizedY: 1 - box.maxY,
                    normalizedWidth: box.width,
                    normalizedHeight: box.height
                )
            }
        } else {
            regions = []
        }

        return TemporalVisualContext(
            foregroundMaskPNG: mask,
            salientRegions: regions
        )
    }

    private nonisolated static func encodedAlphaMask(
        from pixelBuffer: CVPixelBuffer
    ) -> Data? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let maximumDimension = max(source.extent.width, source.extent.height, 1)
        let scale = min(320 / maximumDimension, 1)
        let scaled = source.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let alphaMask = scaled.applyingFilter("CIMaskToAlpha")
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.pngRepresentation(
            of: alphaMask,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [:]
        )
    }
}

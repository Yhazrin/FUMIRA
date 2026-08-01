import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageGenerationRequest: Sendable {
    let photo: CapturedPhoto
    let time: TimePosition
    /// Mock/offline display only. Live remote generation ignores this; the
    /// server authors the prompt from time + optional Scene Bible / beat.
    let prompt: String
    let sessionID: UUID
    let model: AIModelOption
    var understanding: SceneUnderstanding? = nil
    var temporalStory: TemporalStory? = nil
    var storyBeat: StoryBeat? = nil
}

protocol GenerationProvider: Sendable {
    func generate(
        request: ImageGenerationRequest
    ) async -> AsyncThrowingStream<GenerationEvent, Error>
}

actor MockGenerationProvider: GenerationProvider {
    private let stepDelay: Duration
    private let failureMode: FailureMode
    private var remainingForcedFailures: Int

    enum FailureMode: Sendable {
        case none
        /// Fail once, then succeed on subsequent calls (retry coverage).
        case failOnce(GenerationError)
        case always(GenerationError)
    }

    init(
        stepDelay: Duration = .milliseconds(220),
        failureMode: FailureMode = .none
    ) {
        self.stepDelay = stepDelay
        self.failureMode = failureMode
        switch failureMode {
        case .failOnce:
            remainingForcedFailures = 1
        case .always:
            remainingForcedFailures = Int.max
        case .none:
            remainingForcedFailures = 0
        }
    }

    func generate(
        request: ImageGenerationRequest
    ) async -> AsyncThrowingStream<GenerationEvent, Error> {
        let forcedError: GenerationError?
        if remainingForcedFailures > 0 {
            remainingForcedFailures -= 1
            switch failureMode {
            case let .failOnce(error), let .always(error):
                forcedError = error
            case .none:
                forcedError = nil
            }
        } else {
            forcedError = nil
        }

        let delay = stepDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let forcedError {
                        try await Task.sleep(for: delay)
                        throw forcedError
                    }

                    let steps: [(String, Double, GenerationProgressStage)] = [
                        ("收集此刻的种子", 0.12, .uploading),
                        ("把时间埋进画面", 0.28, .preparing),
                        ("时间正在排队生长", 0.42, .queued),
                        ("时间正在生长", 0.58, .processing),
                        ("时间正在生长", 0.72, .processing),
                        ("时间枝叶展开", 0.84, .processing),
                        ("收成这一帧", 0.94, .finishing),
                    ]

                    for step in steps {
                        try Task.checkCancellation()
                        try await Task.sleep(for: delay)
                        continuation.yield(.progress(
                            label: step.0,
                            value: step.1,
                            stage: step.2
                        ))
                    }

                    try Task.checkCancellation()
                    let imageData = MockTemporalImageRenderer.render(
                        sourceData: request.photo.data,
                        normalizedTime: request.time.normalized
                    )

                    continuation.yield(.completed(GeneratedFrame(
                        sessionID: request.sessionID,
                        time: request.time,
                        storyBeatID: request.storyBeat?.id
                            ?? request.temporalStory?.generationBeat(for: request.time)?.id,
                        prompt: request.prompt,
                        modelOptionID: request.model.id,
                        imageData: imageData
                    )))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Bounded, deterministic offline rendering that keeps the source composition
/// intact while making the selected temporal direction visible.
private enum MockTemporalImageRenderer {
    private static let maximumPixelSize = 1_600
    private static let jpegQuality = 0.9

    static func render(sourceData: Data, normalizedTime: Double) -> Data {
        guard
            let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
            let sourceImage = thumbnail(from: source),
            let renderedImage = render(sourceImage, normalizedTime: normalizedTime),
            let encoded = encodeJPEG(renderedImage)
        else {
            return sourceData
        }
        return encoded
    }

    private static func thumbnail(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func render(
        _ sourceImage: CGImage,
        normalizedTime: Double
    ) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: sourceImage.width,
            height: sourceImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        let canvas = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(sourceImage.width),
            height: CGFloat(sourceImage.height)
        )
        context.interpolationQuality = .high
        context.draw(sourceImage, in: canvas)

        // A shared paper cast keeps NOW inside the same mock visual language.
        context.setFillColor(red: 0.96, green: 0.94, blue: 0.87, alpha: 0.028)
        context.fill(canvas)

        let boundedTime = normalizedTime.isFinite
            ? min(max(normalizedTime, -1), 1)
            : 0
        let temporalOpacity = CGFloat(0.28 * abs(boundedTime))
        guard temporalOpacity > 0 else { return context.makeImage() }

        if boundedTime < 0 {
            context.setFillColor(
                red: 0.82,
                green: 0.58,
                blue: 0.30,
                alpha: temporalOpacity
            )
        } else {
            context.setFillColor(
                red: 0.12,
                green: 0.63,
                blue: 0.78,
                alpha: temporalOpacity
            )
        }
        context.fill(canvas)
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
            kCGImagePropertyOrientation: 1,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

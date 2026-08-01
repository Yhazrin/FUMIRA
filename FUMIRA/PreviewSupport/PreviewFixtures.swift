import Foundation
import SwiftUI
import UIKit

@MainActor
enum PreviewFixtures {
    static func model(
        phase: AppPhase,
        time normalized: Double = 0,
        progress: Double = 0,
        photoAspectRatio: CameraAspectRatio = .classic,
        photoIsLandscape: Bool = false
    ) -> AppModel {
        let model = AppModel(dependencies: .preview)
        model.phase = phase
        model.selectedTime = TimePosition(normalized: normalized)
        model.understandingProgress = progress
        model.storyProgress = progress
        model.generationProgress = progress
        model.pipelineStatusText = statusText(for: phase)
        var previewSize = previewPhotoSize(for: photoAspectRatio)
        if photoIsLandscape, previewSize.height > previewSize.width {
            previewSize = (width: previewSize.height, height: previewSize.width)
        }
        model.cameraAspectRatio = photoAspectRatio
        let previewImageData = makePreviewImageData(
            width: previewSize.width,
            height: previewSize.height
        )
        let previewPhoto = CapturedPhoto(
            data: previewImageData,
            pixelWidth: previewSize.width,
            pixelHeight: previewSize.height
        )
        model.capturedPhoto = previewPhoto
        model.decodedCapturedImage = UIImage(data: previewImageData)
        model.decodedMicroTimeSliceFrames = Array(
            repeating: UIImage(data: previewImageData),
            count: 6
        ).compactMap { $0 }
        let foregroundMaskData = makePreviewForegroundMaskData(
            width: previewSize.width,
            height: previewSize.height
        )
        let visualContext = TemporalVisualContext(
            foregroundMaskPNG: foregroundMaskData,
            salientRegions: [
                TemporalSalientRegion(
                    normalizedX: 0.24,
                    normalizedY: 0.37,
                    normalizedWidth: 0.52,
                    normalizedHeight: 0.22
                ),
                TemporalSalientRegion(
                    normalizedX: 0.08,
                    normalizedY: 0.62,
                    normalizedWidth: 0.84,
                    normalizedHeight: 0.30
                ),
            ]
        )
        model.decodedForegroundMask = UIImage(data: foregroundMaskData)
        model.temporalCapturePacket = TemporalCapturePacket(
            photo: previewPhoto,
            origin: .camera,
            composition: photoAspectRatio,
            shutterDate: Date(),
            motion: .unavailable,
            microTimeSlice: MicroTimeSlice(
                duration: 0.7,
                frames: Array(repeating: previewImageData, count: 6)
                    .enumerated()
                    .map { index, data in
                        TemporalFrameSample(
                            offsetFromShutter: Double(index - 3) * 0.1,
                            jpegData: data
                        )
                    }
            ),
            subjectAnchor: TemporalSubjectAnchor(
                normalizedX: 0.68,
                normalizedY: 0.52
            ),
            visualContext: visualContext,
            opticalContext: TemporalOpticalContext(
                lensPosition: .back,
                focusPosition: 0.62,
                exposureDurationSeconds: 1 / 120,
                iso: 80,
                exposureTargetOffset: 0,
                zoomFactor: 1,
                lightCondition: .balanced
            )
        )
        model.sceneUnderstanding = .parkReference
        model.temporalStory = .parkReference
        if phase == .result || phase == .share {
            model.generatedPhoto = CapturedPhoto(
                data: previewImageData,
                pixelWidth: previewSize.width,
                pixelHeight: previewSize.height
            )
            model.generatedFrame = GeneratedFrame(
                sessionID: UUID(),
                time: model.selectedTime,
                storyBeatID: model.temporalStory?.beat(for: model.selectedTime)?.id,
                prompt: TemporalImagePrompt.make(for: model.selectedTime),
                imageData: previewImageData
            )
            model.decodedGeneratedImage = UIImage(data: previewImageData)
        }
        if phase == .connected || phase == .viewfinder {
            model.hardwareSnapshot = HardwareSnapshot(name: "FutureCam_01", batteryLevel: 86)
        }
        if phase == .pipelineFailure || phase == .disconnected {
            model.failedStage = .imageGeneration
            model.lastGenerationError = .timedOut
            model.lastErrorMessage = GenerationError.timedOut.errorDescription
        }
        return model
    }

    private static func previewPhotoSize(
        for aspectRatio: CameraAspectRatio
    ) -> (width: Int, height: Int) {
        switch aspectRatio {
        case .fullScreen:
            (1_179, 2_556)
        case .widescreen:
            (900, 1_600)
        case .classic:
            (900, 1_200)
        case .square:
            (1_200, 1_200)
        }
    }

    private static func statusText(for phase: AppPhase) -> String {
        switch phase {
        case .generating:
            "目标照片正在生长"
        case .understanding:
            "正在读取目标画面"
        case .storyWriting:
            "围绕目标画面编写故事"
        default:
            ""
        }
    }

    private static func makePreviewImageData(width: Int, height: Int) -> Data {
        let ratio = CGFloat(max(width, 1)) / CGFloat(max(height, 1))
        let renderWidth: CGFloat = min(max(CGFloat(width), 320), 900)
        let renderSize = CGSize(
            width: renderWidth,
            height: max(renderWidth / max(ratio, 0.01), 1)
        )
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            let bounds = CGRect(origin: .zero, size: renderSize)
            let graphics = context.cgContext

            let skyGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(PosterPalette.skySoft).cgColor,
                    UIColor(PosterPalette.paper).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )
            if let skyGradient {
                graphics.drawLinearGradient(
                    skyGradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: renderSize.height * 0.68),
                    options: []
                )
            } else {
                UIColor(PosterPalette.skySoft).setFill()
                context.fill(bounds)
            }

            let distantHill = UIBezierPath()
            distantHill.move(to: CGPoint(x: 0, y: renderSize.height * 0.55))
            distantHill.addCurve(
                to: CGPoint(x: renderSize.width, y: renderSize.height * 0.52),
                controlPoint1: CGPoint(x: renderSize.width * 0.28, y: renderSize.height * 0.42),
                controlPoint2: CGPoint(x: renderSize.width * 0.68, y: renderSize.height * 0.63)
            )
            distantHill.addLine(to: CGPoint(x: renderSize.width, y: renderSize.height))
            distantHill.addLine(to: CGPoint(x: 0, y: renderSize.height))
            distantHill.close()
            UIColor(PosterPalette.grassLight).setFill()
            distantHill.fill()

            let foregroundHill = UIBezierPath()
            foregroundHill.move(to: CGPoint(x: 0, y: renderSize.height * 0.72))
            foregroundHill.addCurve(
                to: CGPoint(x: renderSize.width, y: renderSize.height * 0.66),
                controlPoint1: CGPoint(x: renderSize.width * 0.34, y: renderSize.height * 0.62),
                controlPoint2: CGPoint(x: renderSize.width * 0.76, y: renderSize.height * 0.82)
            )
            foregroundHill.addLine(to: CGPoint(x: renderSize.width, y: renderSize.height))
            foregroundHill.addLine(to: CGPoint(x: 0, y: renderSize.height))
            foregroundHill.close()
            UIColor(PosterPalette.leafGreen).setFill()
            foregroundHill.fill()

            let path = UIBezierPath()
            path.move(to: CGPoint(x: renderSize.width * 0.47, y: renderSize.height * 0.55))
            path.addCurve(
                to: CGPoint(x: renderSize.width * 0.78, y: renderSize.height),
                controlPoint1: CGPoint(x: renderSize.width * 0.43, y: renderSize.height * 0.71),
                controlPoint2: CGPoint(x: renderSize.width * 0.62, y: renderSize.height * 0.84)
            )
            path.addLine(to: CGPoint(x: renderSize.width * 0.28, y: renderSize.height))
            path.addCurve(
                to: CGPoint(x: renderSize.width * 0.47, y: renderSize.height * 0.55),
                controlPoint1: CGPoint(x: renderSize.width * 0.42, y: renderSize.height * 0.82),
                controlPoint2: CGPoint(x: renderSize.width * 0.52, y: renderSize.height * 0.69)
            )
            path.close()
            UIColor(PosterPalette.paper).setFill()
            path.fill()

            let trunkWidth = renderSize.width * 0.035
            UIColor(PosterPalette.pine).setFill()
            context.fill(
                CGRect(
                    x: renderSize.width * 0.16,
                    y: renderSize.height * 0.36,
                    width: trunkWidth,
                    height: renderSize.height * 0.42
                )
            )
            context.fill(
                CGRect(
                    x: renderSize.width * 0.78,
                    y: renderSize.height * 0.42,
                    width: trunkWidth * 0.82,
                    height: renderSize.height * 0.30
                )
            )

            UIColor(PosterPalette.pine).setFill()
            for canopy in [
                CGRect(
                    x: renderSize.width * 0.03,
                    y: renderSize.height * 0.18,
                    width: renderSize.width * 0.31,
                    height: renderSize.width * 0.31
                ),
                CGRect(
                    x: renderSize.width * 0.68,
                    y: renderSize.height * 0.28,
                    width: renderSize.width * 0.24,
                    height: renderSize.width * 0.24
                ),
            ] {
                context.cgContext.fillEllipse(in: canopy)
            }
        }
    }

    private static func makePreviewForegroundMaskData(
        width: Int,
        height: Int
    ) -> Data {
        let ratio = CGFloat(max(width, 1)) / CGFloat(max(height, 1))
        let renderWidth: CGFloat = min(max(CGFloat(width), 320), 900)
        let renderSize = CGSize(
            width: renderWidth,
            height: max(renderWidth / max(ratio, 0.01), 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.pngData { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: renderSize))

            UIColor.white.setFill()
            let foregroundCanopy = CGRect(
                x: renderSize.width * 0.03,
                y: renderSize.height * 0.18,
                width: renderSize.width * 0.31,
                height: renderSize.width * 0.31
            )
            UIRectFill(CGRect(
                x: renderSize.width * 0.16,
                y: renderSize.height * 0.36,
                width: renderSize.width * 0.035,
                height: renderSize.height * 0.42
            ))
            UIBezierPath(ovalIn: foregroundCanopy).fill()
        }
    }
}

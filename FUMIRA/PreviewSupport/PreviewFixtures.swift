import Foundation
import SwiftUI

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
        model.capturedPhoto = CapturedPhoto(
            data: Data(),
            pixelWidth: previewSize.width,
            pixelHeight: previewSize.height
        )
        model.sceneUnderstanding = .parkReference
        model.temporalStory = .parkReference
        model.generatedFrame = GeneratedFrame(
            sessionID: UUID(),
            time: model.selectedTime,
            storyBeatID: TemporalStory.parkReference.beat(for: model.selectedTime)?.id,
            prompt: TemporalStory.parkReference.generationPrompt(
                for: model.selectedTime,
                understanding: .parkReference
            )
        )
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
        case .understanding:
            "提取时代线索"
        case .storyWriting:
            "把七个年代连成故事"
        case .generating:
            "时间正在生长"
        default:
            ""
        }
    }
}

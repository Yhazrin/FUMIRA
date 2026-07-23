import Foundation
import SwiftUI

@MainActor
enum PreviewFixtures {
    static func model(
        phase: AppPhase,
        time normalized: Double = 0,
        progress: Double = 0
    ) -> AppModel {
        let model = AppModel(dependencies: .preview)
        model.phase = phase
        model.selectedTime = TimePosition(normalized: normalized)
        model.understandingProgress = progress
        model.storyProgress = progress
        model.generationProgress = progress
        model.pipelineStatusText = statusText(for: phase)
        model.capturedPhoto = CapturedPhoto(data: Data())
        model.sceneUnderstanding = .demoPark
        model.temporalStory = .demoPark
        model.generatedFrame = GeneratedFrame(
            sessionID: UUID(),
            time: model.selectedTime,
            storyBeatID: TemporalStory.demoPark.beat(for: model.selectedTime)?.id,
            prompt: TemporalStory.demoPark.generationPrompt(
                for: model.selectedTime,
                understanding: .demoPark
            )
        )
        if phase == .connected || phase == .viewfinder {
            model.hardwareSnapshot = HardwareSnapshot(name: "FutureCam_01", batteryLevel: 86)
        }
        if phase == .pipelineFailure || phase == .disconnected {
            model.failedStage = .imageGeneration
            model.lastErrorMessage = "目标时间生成超时，当前结果仍然可用。"
        }
        return model
    }

    private static func statusText(for phase: AppPhase) -> String {
        switch phase {
        case .understanding:
            "提取时代线索"
        case .storyWriting:
            "把七个年代连成故事"
        case .generating:
            "注入时间故事"
        default:
            ""
        }
    }
}

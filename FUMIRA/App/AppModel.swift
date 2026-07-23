import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private let dependencies: AppDependencies
    private var hasPrepared = false

    var phase: AppPhase = .connection
    var selectedTime: TimePosition = .now
    var understandingProgress = 0.0
    var storyProgress = 0.0
    var generationProgress = 0.0
    var pipelineStatusText = ""
    var hardwareSnapshot: HardwareSnapshot?
    var activeSessionID: UUID?
    var capturedPhoto: CapturedPhoto?
    var sceneUnderstanding: SceneUnderstanding?
    var temporalStory: TemporalStory?
    var generatedFrame: GeneratedFrame?
    var failedStage: PipelineStage?
    var lastErrorMessage: String?
    var posterURL: URL?
    var modelCatalog: AIModelCatalog = .bundled
    var modelConfiguration: AIModelConfiguration = .demo
    var isModelSettingsPresented = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var isPipelineBusy: Bool {
        switch phase {
        case .shuttered, .understanding, .storyWriting, .generating:
            true
        default:
            false
        }
    }

    var isUsingLiveCamera: Bool {
        dependencies.cameraPreview.isLive
    }

    var cameraPreview: AnyView {
        dependencies.cameraPreview.makePreview()
    }

    var currentNarrative: String {
        temporalStory?.narrative(for: selectedTime)
            ?? "先拍下一张照片，FUMIRA 会读懂画面，再为同一个地方写出跨越时间的故事。"
    }

    var currentStoryBeat: StoryBeat? {
        temporalStory?.beat(for: selectedTime)
    }

    func modelOption(for role: AIModelRole) -> AIModelOption? {
        modelCatalog.option(id: modelConfiguration.optionID(for: role))
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        do {
            modelCatalog = try await dependencies.modelCatalog.catalog()
            let stored = await dependencies.modelConfigurationStore.load()
            modelConfiguration = sanitized(stored)
        } catch {
            modelCatalog = .bundled
            modelConfiguration = .demo
            lastErrorMessage = "模型目录暂时不可用，已切换到本地演示路由。"
        }
    }

    func beginHardwarePath() {
        phase = .bluetoothPermission
    }

    func beginPhoneOnlyPath() {
        phase = .cameraPermission
    }

    func grantBluetoothAndConnect() async {
        do {
            hardwareSnapshot = try await dependencies.hardware.connect()
            phase = .connected
            dependencies.haptics.play(.success)
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .disconnected
        }
    }

    func continueFromConnection() {
        phase = .cameraPermission
    }

    func grantCameraAccess() async {
        do {
            _ = try await dependencies.camera.requestAuthorization()
            phase = .viewfinder
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func capture() async {
        guard validateRunnableConfiguration() else { return }
        let sessionID = UUID()
        activeSessionID = sessionID
        clearPipelineResult()

        do {
            let photo = try await dependencies.camera.capturePhoto()
            guard activeSessionID == sessionID else { return }
            capturedPhoto = photo
            await dependencies.camera.stopPreview()
            phase = .shuttered
            dependencies.haptics.play(.shutter)
            try? await Task.sleep(for: .milliseconds(180))
            guard activeSessionID == sessionID else { return }
            await startUnderstanding(photo: photo, sessionID: sessionID)
        } catch {
            presentFailure(stage: .capture, error: error, sessionID: sessionID)
        }
    }

    func startUnderstanding(photo: CapturedPhoto, sessionID: UUID) async {
        guard let option = modelOption(for: .understanding) else {
            presentConfigurationFailure()
            return
        }
        understandingProgress = 0
        pipelineStatusText = "准备理解画面"
        phase = .understanding

        do {
            let events = await dependencies.understanding.analyze(
                request: ImageUnderstandingRequest(
                    photo: photo,
                    sessionID: sessionID,
                    model: option
                )
            )
            for try await event in events {
                guard activeSessionID == sessionID else { return }
                switch event {
                case let .progress(label, value):
                    pipelineStatusText = label
                    understandingProgress = value
                case let .completed(value):
                    understandingProgress = 1
                    sceneUnderstanding = value
                    await startStoryWriting(understanding: value, sessionID: sessionID)
                }
            }
        } catch {
            presentFailure(stage: .understanding, error: error, sessionID: sessionID)
        }
    }

    func startStoryWriting(
        understanding: SceneUnderstanding,
        sessionID: UUID
    ) async {
        guard let option = modelOption(for: .story) else {
            presentConfigurationFailure()
            return
        }
        storyProgress = 0
        pipelineStatusText = "准备时间线"
        phase = .storyWriting

        do {
            let events = await dependencies.story.write(
                request: StoryRequest(
                    understanding: understanding,
                    sessionID: sessionID,
                    model: option
                )
            )
            for try await event in events {
                guard activeSessionID == sessionID else { return }
                switch event {
                case let .progress(label, value):
                    pipelineStatusText = label
                    storyProgress = value
                case let .completed(value):
                    storyProgress = 1
                    temporalStory = value
                    phase = .storyReady
                    dependencies.haptics.play(.success)
                }
            }
        } catch {
            presentFailure(stage: .story, error: error, sessionID: sessionID)
        }
    }

    func generateStoryWorld() async {
        guard
            let photo = capturedPhoto,
            let understanding = sceneUnderstanding,
            let story = temporalStory,
            let option = modelOption(for: .image)
        else {
            presentConfigurationFailure()
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        generationProgress = 0
        pipelineStatusText = "准备生成故事画面"
        failedStage = nil
        phase = .generating

        do {
            let events = await dependencies.generation.generate(
                request: ImageGenerationRequest(
                    photo: photo,
                    understanding: understanding,
                    story: story,
                    time: selectedTime,
                    sessionID: sessionID,
                    model: option
                )
            )
            for try await event in events {
                guard activeSessionID == sessionID else { return }
                switch event {
                case let .progress(value):
                    generationProgress = value
                case let .completed(frame):
                    generatedFrame = frame
                    generationProgress = 1
                    phase = .result
                    dependencies.haptics.play(.success)
                }
            }
        } catch {
            presentFailure(stage: .imageGeneration, error: error, sessionID: sessionID)
        }
    }

    func regenerateStory() async {
        guard let understanding = sceneUnderstanding else {
            retake()
            return
        }
        let sessionID = UUID()
        activeSessionID = sessionID
        temporalStory = nil
        await startStoryWriting(understanding: understanding, sessionID: sessionID)
    }

    func retryPipeline() async {
        guard let stage = failedStage else {
            retake()
            return
        }
        let sessionID = UUID()
        activeSessionID = sessionID
        failedStage = nil
        lastErrorMessage = nil

        switch stage {
        case .configuration:
            isModelSettingsPresented = true
            phase = capturedPhoto == nil ? .viewfinder : .storyReady
        case .capture:
            phase = .viewfinder
            await resumeCameraPreview()
        case .understanding:
            if let photo = capturedPhoto {
                await startUnderstanding(photo: photo, sessionID: sessionID)
            } else {
                retake()
            }
        case .story:
            if let understanding = sceneUnderstanding {
                await startStoryWriting(understanding: understanding, sessionID: sessionID)
            } else if let photo = capturedPhoto {
                await startUnderstanding(photo: photo, sessionID: sessionID)
            }
        case .imageGeneration:
            await generateStoryWorld()
        }
    }

    func showOriginalNow() {
        activeSessionID = nil
        selectedTime = .now
        if temporalStory != nil {
            phase = .result
        } else if sceneUnderstanding != nil {
            phase = .storyWriting
        } else {
            phase = .viewfinder
            Task { await resumeCameraPreview() }
        }
    }

    func updateTime(normalized: Double) {
        selectedTime = TimePosition(normalized: normalized)
    }

    func openShare() {
        phase = .share
    }

    func returnToResult() {
        phase = .result
    }

    func retake() {
        activeSessionID = nil
        clearPipelineResult()
        phase = .viewfinder
        Task { await resumeCameraPreview() }
    }

    func recoverConnection() {
        phase = .connection
    }

    func presentFailureForPreview() {
        activeSessionID = nil
        failedStage = .imageGeneration
        lastErrorMessage = "变迁图生成超时。识图结果和时间故事已经保留。"
        phase = .pipelineFailure
    }

    func selectModel(optionID: String, for role: AIModelRole) async {
        guard
            let option = modelCatalog.option(id: optionID),
            option.role == role,
            option.availability == .ready
        else {
            lastErrorMessage = "这个模型路由还需要后台接入后才能启用。"
            return
        }
        modelConfiguration.select(optionID: optionID, for: role)
        do {
            try await dependencies.modelConfigurationStore.save(modelConfiguration)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "模型选择已在本次运行生效，但暂时无法保存。"
        }
    }

    private func sanitized(
        _ configuration: AIModelConfiguration
    ) -> AIModelConfiguration {
        var result = configuration
        for role in AIModelRole.allCases {
            guard
                let option = modelCatalog.option(id: configuration.optionID(for: role)),
                option.role == role,
                option.availability == .ready
            else {
                result.select(optionID: AIModelConfiguration.demo.optionID(for: role), for: role)
                continue
            }
        }
        return result
    }

    private func validateRunnableConfiguration() -> Bool {
        guard modelCatalog.isRunnable(modelConfiguration) else {
            presentConfigurationFailure()
            return false
        }
        return true
    }

    private func presentConfigurationFailure() {
        activeSessionID = nil
        failedStage = .configuration
        lastErrorMessage = "当前模型组合尚未全部接通，请在模型后台选择可运行路由。"
        phase = .pipelineFailure
    }

    private func presentFailure(
        stage: PipelineStage,
        error: Error,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        failedStage = stage
        lastErrorMessage = error.localizedDescription
        phase = .pipelineFailure
    }

    private func resumeCameraPreview() async {
        do {
            try await dependencies.camera.startPreview()
        } catch {
            lastErrorMessage = error.localizedDescription
            failedStage = .capture
            phase = .pipelineFailure
        }
    }

    private func clearPipelineResult() {
        capturedPhoto = nil
        sceneUnderstanding = nil
        temporalStory = nil
        generatedFrame = nil
        understandingProgress = 0
        storyProgress = 0
        generationProgress = 0
        pipelineStatusText = ""
        failedStage = nil
        lastErrorMessage = nil
    }
}

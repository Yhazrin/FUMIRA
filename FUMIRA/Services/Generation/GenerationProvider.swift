import Foundation

struct ImageGenerationRequest: Sendable {
    let photo: CapturedPhoto
    let understanding: SceneUnderstanding
    let story: TemporalStory
    let time: TimePosition
    let sessionID: UUID
    let model: AIModelOption
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

                    continuation.yield(.completed(GeneratedFrame(
                        sessionID: request.sessionID,
                        time: request.time,
                        storyBeatID: request.story.generationBeat(for: request.time)?.id,
                        prompt: "[mock-compiled]",
                        modelOptionID: request.model.id,
                        imageData: nil
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

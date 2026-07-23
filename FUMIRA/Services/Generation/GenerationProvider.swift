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

    init(stepDelay: Duration = .milliseconds(220)) {
        self.stepDelay = stepDelay
    }

    func generate(
        request: ImageGenerationRequest
    ) async -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for step in 1...8 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: stepDelay)
                    continuation.yield(.progress(Double(step) / 8))
                }
                continuation.yield(.completed(GeneratedFrame(
                    sessionID: request.sessionID,
                    time: request.time,
                    storyBeatID: request.story.beat(for: request.time)?.id,
                    prompt: request.story.generationPrompt(
                        for: request.time,
                        understanding: request.understanding
                    ),
                    modelOptionID: request.model.id,
                    imageData: nil
                )))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

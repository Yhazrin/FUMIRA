import Foundation

struct StoryRequest: Sendable {
    let understanding: SceneUnderstanding
    /// The year selected on the viewfinder when this photo was captured.
    let targetTime: TimePosition
    let sessionID: UUID
    let model: AIModelOption
}

enum StoryEvent: Sendable {
    case progress(label: String, value: Double)
    case completed(TemporalStory)
}

protocol StoryProvider: Sendable {
    func write(request: StoryRequest) async -> AsyncThrowingStream<StoryEvent, Error>
    /// Generate a single exact target beat for browse-year generation.
    func writeTargetBeat(
        understanding: SceneUnderstanding,
        story: TemporalStory,
        target: TimePosition
    ) async throws -> StoryBeat
}

actor MockStoryProvider: StoryProvider {
    private let stepDelay: Duration

    init(stepDelay: Duration = .milliseconds(260)) {
        self.stepDelay = stepDelay
    }

    func writeTargetBeat(
        understanding: SceneUnderstanding,
        story: TemporalStory,
        target: TimePosition
    ) async throws -> StoryBeat {
        guard let beat = TemporalStory.fallback(
            understanding: understanding,
            targetTime: target
        ).targetBeat else {
            throw GenerationError.generationFailed(message: "无法建立精确目标场景计划。")
        }
        return beat
    }

    func write(request: StoryRequest) async -> AsyncThrowingStream<StoryEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let steps = [
                    ("守住原图里的身份", 0.2),
                    ("回看一百年前", 0.45),
                    ("推演一百年后", 0.7),
                    ("把七个年代连成故事", 1.0)
                ]
                for step in steps {
                    try Task.checkCancellation()
                    try await Task.sleep(for: stepDelay)
                    continuation.yield(.progress(label: step.0, value: step.1))
                }
                continuation.yield(.completed(.fallback(
                    understanding: request.understanding,
                    targetTime: request.targetTime
                )))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

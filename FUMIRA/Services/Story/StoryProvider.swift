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
        let location = understanding.locationType.isEmpty ? "这个地方" : understanding.locationType
        let driver = understanding.changeDrivers.first ?? "时间自然变化"
        let targetIdentity = ExactTarget(
            offsetDays: target.offsetDays,
            targetDateISO: target.targetDate().ISO8601Format(),
            compactLabel: target.compactLabel
        )
        return StoryBeat(
            anchorYears: target.offsetYears,
            title: "\(location)的\(target.compactLabel)",
            narrative: "\(driver)在\(target.compactLabel)深刻改变\(location)的面貌，主体与构图保持连续。",
            visualPrompt: "\(understanding.visualMood)，\(driver)经过\(target.compactLabel)的累积效应，保持原图主体、机位与构图",
            exactTarget: targetIdentity
        )
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

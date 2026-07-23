import Foundation

struct StoryRequest: Sendable {
    let understanding: SceneUnderstanding
    let sessionID: UUID
    let model: AIModelOption
}

enum StoryEvent: Sendable {
    case progress(label: String, value: Double)
    case completed(TemporalStory)
}

protocol StoryProvider: Sendable {
    func write(request: StoryRequest) async -> AsyncThrowingStream<StoryEvent, Error>
}

actor MockStoryProvider: StoryProvider {
    private let stepDelay: Duration

    init(stepDelay: Duration = .milliseconds(260)) {
        self.stepDelay = stepDelay
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
                continuation.yield(.completed(.demoPark))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

import Foundation

struct ImageUnderstandingRequest: Sendable {
    let photo: CapturedPhoto
    let sessionID: UUID
    let model: AIModelOption
}

enum UnderstandingEvent: Sendable {
    case progress(label: String, value: Double)
    case completed(SceneUnderstanding)
}

protocol ImageUnderstandingProvider: Sendable {
    func analyze(
        request: ImageUnderstandingRequest
    ) async -> AsyncThrowingStream<UnderstandingEvent, Error>
}

actor MockImageUnderstandingProvider: ImageUnderstandingProvider {
    private let stepDelay: Duration

    init(stepDelay: Duration = .milliseconds(240)) {
        self.stepDelay = stepDelay
    }

    func analyze(
        request: ImageUnderstandingRequest
    ) async -> AsyncThrowingStream<UnderstandingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let steps = [
                    ("寻找画面主体", 0.22),
                    ("理解空间与构图", 0.48),
                    ("提取时代线索", 0.74),
                    ("推演变化驱动", 1.0)
                ]
                for step in steps {
                    try Task.checkCancellation()
                    try await Task.sleep(for: stepDelay)
                    continuation.yield(.progress(label: step.0, value: step.1))
                }
                continuation.yield(.completed(.parkReference))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

import Foundation

struct ImageUnderstandingRequest: Sendable {
    let photo: CapturedPhoto
    /// Target browsing time used while building the source Scene Bible.
    let targetTime: TimePosition
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
                    ("封存源照片", 0.22),
                    ("读取空间与构图", 0.48),
                    ("锁定时间层与锚点", 0.74),
                    ("整理场景圣经", 1.0)
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

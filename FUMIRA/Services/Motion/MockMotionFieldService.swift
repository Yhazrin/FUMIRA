import Foundation

actor MotionFieldServiceState {
    private var continuation: AsyncStream<MotionFieldSample>.Continuation?
    private var isRunning = false

    func setContinuation(_ continuation: AsyncStream<MotionFieldSample>.Continuation) {
        self.continuation = continuation
    }

    func clearContinuation() {
        continuation?.finish()
        continuation = nil
    }

    func beginIfNeeded() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    func end() {
        isRunning = false
        continuation?.finish()
        continuation = nil
    }

    func yield(_ sample: MotionFieldSample) {
        continuation?.yield(sample)
    }

    var running: Bool {
        isRunning
    }
}

final class MockMotionFieldService: MotionFieldProviding, @unchecked Sendable {
    private let state = MotionFieldServiceState()

    func samples() -> AsyncStream<MotionFieldSample> {
        AsyncStream { continuation in
            Task {
                await state.setContinuation(continuation)
            }
        }
    }

    func start() async {
        _ = await state.beginIfNeeded()
    }

    func stop() async {
        await state.end()
    }
}

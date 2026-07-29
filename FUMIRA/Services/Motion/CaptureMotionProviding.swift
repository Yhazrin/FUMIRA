import Foundation

protocol CaptureMotionProviding: Sendable {
    func samples() -> AsyncStream<CaptureMotionSample>
    func start() async
    func stop() async
}

actor CaptureMotionStreamState {
    private var continuation: AsyncStream<CaptureMotionSample>.Continuation?
    private var running = false

    func install(_ continuation: AsyncStream<CaptureMotionSample>.Continuation) {
        self.continuation?.finish()
        self.continuation = continuation
    }

    func beginIfNeeded() -> Bool {
        guard !running else { return false }
        running = true
        return true
    }

    func yield(_ sample: CaptureMotionSample) {
        guard running else { return }
        continuation?.yield(sample)
    }

    func end() {
        running = false
        continuation?.finish()
        continuation = nil
    }
}

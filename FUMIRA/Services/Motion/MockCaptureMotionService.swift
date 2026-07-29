import Foundation

actor MockCaptureMotionService: CaptureMotionProviding {
    private var continuation: AsyncStream<CaptureMotionSample>.Continuation?
    private var sampleTask: Task<Void, Never>?

    nonisolated func samples() -> AsyncStream<CaptureMotionSample> {
        AsyncStream { continuation in
            Task {
                await self.install(continuation)
            }
        }
    }

    func start() {
        guard sampleTask == nil else { return }
        sampleTask = Task {
            var index = 0
            while !Task.isCancelled {
                let settle = min(Double(index) / 26, 1)
                let wobble = sin(Double(index) * 0.28) * (1 - settle)
                continuation?.yield(
                    CaptureMotionSample(
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        roll: wobble * 0.08,
                        pitch: cos(Double(index) * 0.21) * 0.05 * (1 - settle),
                        yaw: 0,
                        rotationRate: abs(wobble) * 0.7,
                        acceleration: abs(wobble) * 0.08,
                        stability: 0.34 + settle * 0.62
                    )
                )
                index += 1
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func install(
        _ continuation: AsyncStream<CaptureMotionSample>.Continuation
    ) {
        self.continuation?.finish()
        self.continuation = continuation
    }
}

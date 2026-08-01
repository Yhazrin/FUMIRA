import Foundation

enum TemporalShakeAvailability: Equatable, Sendable {
    case unknown
    case motionShakeResponder
    case fallbackRequired
}

struct TemporalShakeSample: Equatable, Sendable {
    /// Normalized impulse strength. Values may exceed one; the reducer bounds
    /// behavior through its threshold rather than mutating the sample.
    let intensity: Double
    let timestamp: TimeInterval
}

enum TemporalShakeServiceEvent: Equatable, Sendable {
    case availability(TemporalShakeAvailability)
    case systemShakeEnded(timestamp: TimeInterval)
    case sample(TemporalShakeSample)
}

/// Short-lived shake input. Implementations must not own a CMMotionManager.
@MainActor
protocol TemporalShakeProviding: AnyObject, Sendable {
    func events() -> AsyncStream<TemporalShakeServiceEvent>
    func start()
    func stop()
}

@MainActor
final class MockTemporalShakeService: TemporalShakeProviding {
    private let configuredAvailability: TemporalShakeAvailability
    private var continuation: AsyncStream<TemporalShakeServiceEvent>.Continuation?
    private var isStarted = false

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(availability: TemporalShakeAvailability = .motionShakeResponder) {
        configuredAvailability = availability
    }

    func events() -> AsyncStream<TemporalShakeServiceEvent> {
        AsyncStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        startCallCount += 1
        continuation?.yield(.availability(configuredAvailability))

        if configuredAvailability == .fallbackRequired {
            isStarted = false
            continuation?.finish()
            continuation = nil
        }
    }

    func stop() {
        guard isStarted || continuation != nil else { return }
        if isStarted {
            stopCallCount += 1
        }
        isStarted = false
        continuation?.finish()
        continuation = nil
    }

    func emitSystemShake(at timestamp: TimeInterval) {
        guard isStarted else { return }
        continuation?.yield(.systemShakeEnded(timestamp: timestamp))
    }

    func emitSample(intensity: Double, at timestamp: TimeInterval) {
        guard isStarted else { return }
        continuation?.yield(
            .sample(
                TemporalShakeSample(
                    intensity: intensity,
                    timestamp: timestamp
                )
            )
        )
    }
}

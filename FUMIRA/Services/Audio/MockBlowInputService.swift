import Foundation

@MainActor
final class MockBlowInputService: BlowInputProviding {
    private let configuredAvailability: BlowInputAvailability
    private var continuation: AsyncStream<BlowInputEvent>.Continuation?
    private var isStarted = false

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(availability: BlowInputAvailability = .liveMicrophone) {
        configuredAvailability = availability
    }

    func events() -> AsyncStream<BlowInputEvent> {
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

        if case .fallbackRequired = configuredAvailability {
            isStarted = false
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

    func emit(decibels: Double, at timestamp: TimeInterval) {
        guard isStarted, configuredAvailability == .liveMicrophone else { return }
        continuation?.yield(
            .level(
                BlowInputLevelSample(
                    decibels: decibels,
                    timestamp: timestamp
                )
            )
        )
    }

    func emitFallback(_ reason: BlowInputFallbackReason) {
        guard isStarted else { return }
        isStarted = false
        continuation?.yield(.availability(.fallbackRequired(reason)))
    }
}

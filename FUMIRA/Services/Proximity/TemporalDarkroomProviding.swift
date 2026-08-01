import Foundation

enum TemporalDarkroomAvailability: Equatable, Sendable {
    case unknown
    case proximitySensor
    case alternativeInputRequired
}

enum TemporalDarkroomInputState: Equatable, Sendable {
    case near
    case far
}

enum TemporalDarkroomInputSource: Equatable, Sendable {
    case proximitySensor
    case alternative
}

struct TemporalDarkroomObservation: Equatable, Sendable {
    let state: TemporalDarkroomInputState
    let source: TemporalDarkroomInputSource
    let timestamp: TimeInterval
}

enum TemporalDarkroomEvent: Equatable, Sendable {
    case availability(TemporalDarkroomAvailability)
    case observation(TemporalDarkroomObservation)
}

/// Supplies the binary near/far input used by the temporal darkroom.
///
/// The alternative input is intentionally part of the same protocol. Simulator,
/// unsupported hardware, and accessible controls can therefore drive exactly the
/// same state engine as the physical proximity sensor.
@MainActor
protocol TemporalDarkroomProviding: AnyObject, Sendable {
    func events() -> AsyncStream<TemporalDarkroomEvent>
    func start()
    func stop()
    func setAlternativeInputActive(_ isActive: Bool, timestamp: TimeInterval)
}

@MainActor
final class MockTemporalDarkroomService: TemporalDarkroomProviding {
    private let configuredAvailability: TemporalDarkroomAvailability
    private let initialState: TemporalDarkroomInputState
    private let clock: @Sendable () -> TimeInterval
    private var continuation: AsyncStream<TemporalDarkroomEvent>.Continuation?
    private var isStarted = false

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(
        availability: TemporalDarkroomAvailability = .alternativeInputRequired,
        initialState: TemporalDarkroomInputState = .far,
        clock: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        configuredAvailability = availability
        self.initialState = initialState
        self.clock = clock
    }

    func events() -> AsyncStream<TemporalDarkroomEvent> {
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
        continuation?.yield(
            .observation(
                TemporalDarkroomObservation(
                    state: initialState,
                    source: configuredAvailability == .proximitySensor
                        ? .proximitySensor
                        : .alternative,
                    timestamp: clock()
                )
            )
        )
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

    func setAlternativeInputActive(_ isActive: Bool, timestamp: TimeInterval) {
        emit(
            state: isActive ? .near : .far,
            source: .alternative,
            timestamp: timestamp
        )
    }

    func emitSensorState(
        _ state: TemporalDarkroomInputState,
        timestamp: TimeInterval
    ) {
        emit(state: state, source: .proximitySensor, timestamp: timestamp)
    }

    func emitAvailability(_ availability: TemporalDarkroomAvailability) {
        guard isStarted else { return }
        continuation?.yield(.availability(availability))
    }

    private func emit(
        state: TemporalDarkroomInputState,
        source: TemporalDarkroomInputSource,
        timestamp: TimeInterval
    ) {
        guard isStarted else { return }
        continuation?.yield(
            .observation(
                TemporalDarkroomObservation(
                    state: state,
                    source: source,
                    timestamp: timestamp
                )
            )
        )
    }
}

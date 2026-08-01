import Foundation
import Observation

struct TemporalDarkroomPolicy: Equatable, Sendable {
    let requiredExposureDuration: TimeInterval
    let departureHoldDuration: TimeInterval
    let decayPerSecond: Double
    let normalTickInterval: TimeInterval
    let reduceMotionTickInterval: TimeInterval

    static let standard = TemporalDarkroomPolicy(
        requiredExposureDuration: 2.4,
        departureHoldDuration: 0.8,
        decayPerSecond: 0.22,
        normalTickInterval: 1.0 / 30.0,
        reduceMotionTickInterval: 0.2
    )

    init(
        requiredExposureDuration: TimeInterval,
        departureHoldDuration: TimeInterval,
        decayPerSecond: Double,
        normalTickInterval: TimeInterval = 1.0 / 30.0,
        reduceMotionTickInterval: TimeInterval = 0.2
    ) {
        self.requiredExposureDuration = Self.positiveFinite(
            requiredExposureDuration,
            fallback: 2.4
        )
        self.departureHoldDuration = Self.nonnegativeFinite(
            departureHoldDuration,
            fallback: 0.8
        )
        self.decayPerSecond = Self.nonnegativeFinite(
            decayPerSecond,
            fallback: 0.22
        )
        self.normalTickInterval = Self.positiveFinite(
            normalTickInterval,
            fallback: 1.0 / 30.0
        )
        self.reduceMotionTickInterval = Self.positiveFinite(
            reduceMotionTickInterval,
            fallback: 0.2
        )
    }

    private static func positiveFinite(
        _ value: Double,
        fallback: Double
    ) -> Double {
        value.isFinite ? max(0.001, value) : fallback
    }

    private static func nonnegativeFinite(
        _ value: Double,
        fallback: Double
    ) -> Double {
        value.isFinite ? max(0, value) : fallback
    }
}

enum TemporalDarkroomPhase: Equatable, Sendable {
    case idle
    case developing
    case holding
    case receding
    case developed
    case suspended
    case cancelled
}

struct TemporalDarkroomSnapshot: Equatable, Sendable {
    let progress: Double
    let phase: TemporalDarkroomPhase
    let inputState: TemporalDarkroomInputState
    let isProcessingActive: Bool
    let reduceMotion: Bool

    var isDeveloped: Bool {
        phase == .developed
    }

    var shouldAnimateProgress: Bool {
        !reduceMotion
    }
}

/// Deterministic exposure state machine. It has no timers, UIKit, or process
/// lifecycle dependencies; callers advance it with monotonic timestamps.
struct TemporalDarkroomEngine: Sendable {
    let policy: TemporalDarkroomPolicy

    private(set) var progress = 0.0
    private(set) var phase: TemporalDarkroomPhase = .idle
    private(set) var inputState: TemporalDarkroomInputState = .far
    private(set) var isProcessingActive = false
    private(set) var reduceMotion = false

    private var lastTimestamp: TimeInterval?
    private var farElapsed = 0.0
    private var isCancelled = false

    init(
        policy: TemporalDarkroomPolicy = .standard,
        reduceMotion: Bool = false
    ) {
        self.policy = policy
        self.reduceMotion = reduceMotion
    }

    var snapshot: TemporalDarkroomSnapshot {
        TemporalDarkroomSnapshot(
            progress: progress,
            phase: phase,
            inputState: inputState,
            isProcessingActive: isProcessingActive,
            reduceMotion: reduceMotion
        )
    }

    mutating func reset(at timestamp: TimeInterval) {
        let timestamp = timestamp.isFinite ? timestamp : 0
        progress = 0
        phase = .idle
        inputState = .far
        isProcessingActive = false
        lastTimestamp = timestamp
        farElapsed = 0
        isCancelled = false
    }

    mutating func setProcessingActive(
        _ isActive: Bool,
        at timestamp: TimeInterval
    ) {
        guard !isCancelled, timestamp.isFinite else { return }

        if isProcessingActive {
            advance(to: timestamp)
        }
        isProcessingActive = isActive
        lastTimestamp = max(lastTimestamp ?? timestamp, timestamp)
        updatePhase()
    }

    mutating func setReduceMotion(_ isEnabled: Bool) {
        reduceMotion = isEnabled
    }

    mutating func ingest(
        _ state: TemporalDarkroomInputState,
        at timestamp: TimeInterval
    ) {
        guard !isCancelled, timestamp.isFinite else { return }
        guard timestamp >= (lastTimestamp ?? timestamp) else { return }

        advance(to: timestamp)
        guard state != inputState else {
            updatePhase()
            return
        }

        inputState = state
        farElapsed = 0
        updatePhase()
    }

    mutating func advance(to timestamp: TimeInterval) {
        guard !isCancelled, timestamp.isFinite else { return }

        guard let previousTimestamp = lastTimestamp else {
            lastTimestamp = timestamp
            updatePhase()
            return
        }
        guard timestamp >= previousTimestamp else { return }

        lastTimestamp = timestamp
        let elapsed = timestamp - previousTimestamp
        guard isProcessingActive, elapsed > 0, progress < 1 else {
            updatePhase()
            return
        }

        switch inputState {
        case .near:
            progress = min(
                1,
                progress + elapsed / policy.requiredExposureDuration
            )
            farElapsed = 0

        case .far:
            let previousFarElapsed = farElapsed
            farElapsed += elapsed
            let previousDecayStart = max(
                0,
                previousFarElapsed - policy.departureHoldDuration
            )
            let nextDecayStart = max(
                0,
                farElapsed - policy.departureHoldDuration
            )
            let decayDuration = nextDecayStart - previousDecayStart
            progress = max(0, progress - decayDuration * policy.decayPerSecond)
        }

        updatePhase()
    }

    mutating func cancel(at timestamp: TimeInterval) {
        guard !isCancelled else { return }
        if timestamp.isFinite {
            advance(to: timestamp)
        }
        isCancelled = true
        isProcessingActive = false
        phase = .cancelled
    }

    private mutating func updatePhase() {
        if isCancelled {
            phase = .cancelled
        } else if progress >= 1 {
            phase = .developed
        } else if !isProcessingActive {
            phase = progress > 0 ? .suspended : .idle
        } else if inputState == .near {
            phase = .developing
        } else if progress <= 0 {
            phase = .idle
        } else if farElapsed <= policy.departureHoldDuration {
            phase = .holding
        } else {
            phase = .receding
        }
    }
}

@MainActor
@Observable
final class TemporalDarkroomModel {
    private let service: any TemporalDarkroomProviding
    private let clock: @Sendable () -> TimeInterval
    private var engine: TemporalDarkroomEngine
    private var consumeTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var monitoringGeneration = 0
    private var sceneIsActive = true

    private(set) var snapshot: TemporalDarkroomSnapshot
    private(set) var availability: TemporalDarkroomAvailability = .unknown
    private(set) var lastInputSource: TemporalDarkroomInputSource?
    private(set) var isActive = false
    private(set) var isMonitoring = false

    var alternativeInputRecommended: Bool {
        availability != .proximitySensor || snapshot.reduceMotion
    }

    init(
        service: any TemporalDarkroomProviding,
        policy: TemporalDarkroomPolicy = .standard,
        clock: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.service = service
        self.clock = clock
        let engine = TemporalDarkroomEngine(policy: policy)
        self.engine = engine
        snapshot = engine.snapshot
    }

    func activate(reduceMotion: Bool) {
        setReduceMotion(reduceMotion)
        guard !isActive else {
            startMonitoringIfNeeded()
            return
        }

        isActive = true
        let timestamp = clock()
        engine.setProcessingActive(sceneIsActive, at: timestamp)
        publishSnapshot()
        startMonitoringIfNeeded()
    }

    /// Stops hardware work while preserving exposure progress for a later resume.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        suspendProcessing(at: clock())
        stopMonitoring()
    }

    func setSceneActive(_ isActive: Bool) {
        guard sceneIsActive != isActive else { return }
        sceneIsActive = isActive
        let timestamp = clock()

        if isActive, self.isActive {
            engine.setProcessingActive(true, at: timestamp)
            publishSnapshot()
            startMonitoringIfNeeded()
        } else {
            suspendProcessing(at: timestamp)
            stopMonitoring()
        }
    }

    func setReduceMotion(_ isEnabled: Bool) {
        guard snapshot.reduceMotion != isEnabled else { return }
        engine.setReduceMotion(isEnabled)
        publishSnapshot()

        if isMonitoring {
            startTicker()
        }
    }

    /// Call from a press-and-hold fallback control. Releasing or cancelling the
    /// gesture must call this with `false`.
    func setAlternativeInputActive(_ isActive: Bool) {
        guard self.isActive, sceneIsActive, isMonitoring else { return }
        service.setAlternativeInputActive(isActive, timestamp: clock())
    }

    func cancel() {
        guard snapshot.phase != .cancelled else { return }
        isActive = false
        engine.cancel(at: clock())
        publishSnapshot()
        stopMonitoring()
    }

    func reset() {
        let timestamp = clock()
        let reduceMotion = snapshot.reduceMotion
        engine.reset(at: timestamp)
        engine.setReduceMotion(reduceMotion)
        engine.setProcessingActive(isActive && sceneIsActive, at: timestamp)
        lastInputSource = nil
        publishSnapshot()
    }

    private func startMonitoringIfNeeded() {
        guard isActive, sceneIsActive, !isMonitoring else { return }

        monitoringGeneration += 1
        let generation = monitoringGeneration
        let stream = service.events()
        isMonitoring = true
        service.start()
        startTicker()

        consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await event in stream {
                guard !Task.isCancelled else { break }
                guard generation == monitoringGeneration else { break }
                handle(event)
            }

            guard !Task.isCancelled, generation == monitoringGeneration else {
                return
            }
            isMonitoring = false
            tickerTask?.cancel()
            tickerTask = nil
        }
    }

    private func stopMonitoring() {
        monitoringGeneration += 1
        consumeTask?.cancel()
        consumeTask = nil
        tickerTask?.cancel()
        tickerTask = nil
        service.stop()
        isMonitoring = false
    }

    private func startTicker() {
        tickerTask?.cancel()
        let interval = snapshot.reduceMotion
            ? engine.policy.reduceMotionTickInterval
            : engine.policy.normalTickInterval

        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
                guard let self, !Task.isCancelled else { break }
                tick()
            }
        }
    }

    private func handle(_ event: TemporalDarkroomEvent) {
        switch event {
        case let .availability(availability):
            self.availability = availability

        case let .observation(observation):
            lastInputSource = observation.source
            engine.ingest(observation.state, at: observation.timestamp)
            publishSnapshot()
        }
    }

    private func tick() {
        engine.advance(to: clock())
        publishSnapshot()
    }

    private func suspendProcessing(at timestamp: TimeInterval) {
        // Clear a held fallback/sensor state before pausing. On resume, the
        // provider publishes its current state, so no stale "near" can develop.
        engine.ingest(.far, at: timestamp)
        engine.setProcessingActive(false, at: timestamp)
        publishSnapshot()
    }

    private func publishSnapshot() {
        let nextSnapshot = engine.snapshot
        guard nextSnapshot != snapshot else { return }
        snapshot = nextSnapshot
    }
}

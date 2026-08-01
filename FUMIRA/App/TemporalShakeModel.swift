import Foundation
import Observation

enum TemporalShakeBranchEvent: Equatable, Sendable {
    case advanceBranch(
        source: TemporalShakeTriggerSource,
        timestamp: TimeInterval
    )
}

/// Short-lived coordinator for the optional shake gesture.
///
/// It never owns time state, branch selection, or generation work. Integration
/// observes only ``latestEvent`` and decides how an `advanceBranch` request maps
/// onto existing product state.
@MainActor
@Observable
final class TemporalShakeModel {
    private let service: any TemporalShakeProviding
    private let clock: @Sendable () -> TimeInterval
    private var reducer: TemporalShakeReducer
    private var consumeTask: Task<Void, Never>?
    private var listeningWindowTask: Task<Void, Never>?
    private var monitoringGeneration = 0
    private var sceneIsActive = true
    private var listeningWindowExpired = false

    private(set) var latestEvent: TemporalShakeBranchEvent?
    private(set) var availability: TemporalShakeAvailability = .unknown
    private(set) var isActive = false
    private(set) var isMonitoring = false
    private(set) var reduceMotion = false

    var fallbackRecommended: Bool {
        reduceMotion
            || availability != .motionShakeResponder
            || !isMonitoring
    }

    init(
        service: any TemporalShakeProviding,
        policy: TemporalShakeDetectionPolicy = .standard,
        clock: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.service = service
        self.clock = clock
        reducer = TemporalShakeReducer(policy: policy)
    }

    func activate(reduceMotion: Bool) {
        if isActive {
            setReduceMotion(reduceMotion)
            return
        }

        self.reduceMotion = reduceMotion
        isActive = true
        latestEvent = nil
        listeningWindowExpired = false
        reducer.reset()

        guard !reduceMotion else { return }
        startMonitoringIfNeeded()
    }

    func deactivate() {
        guard isActive || isMonitoring else { return }
        isActive = false
        listeningWindowExpired = false
        stopMonitoring()
    }

    func setSceneActive(_ isActive: Bool) {
        guard sceneIsActive != isActive else { return }
        sceneIsActive = isActive

        if isActive {
            listeningWindowExpired = false
            startMonitoringIfNeeded()
        } else {
            stopMonitoring()
        }
    }

    func setReduceMotion(_ isEnabled: Bool) {
        guard reduceMotion != isEnabled else { return }
        reduceMotion = isEnabled
        listeningWindowExpired = false

        if isEnabled {
            stopMonitoring()
        } else {
            startMonitoringIfNeeded()
        }
    }

    /// Button-accessible fallback. It follows the same debounce policy as the
    /// responder and external sample paths.
    func requestFallbackAdvance() {
        guard isActive, sceneIsActive else { return }
        publishIfDetected(
            reducer.reduce(.fallbackRequested(timestamp: clock()))
        )
    }

    private func startMonitoringIfNeeded() {
        guard isActive,
              sceneIsActive,
              !reduceMotion,
              !listeningWindowExpired,
              !isMonitoring else {
            return
        }

        monitoringGeneration += 1
        let generation = monitoringGeneration
        let stream = service.events()
        isMonitoring = true
        service.start()

        consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in stream {
                guard !Task.isCancelled, generation == monitoringGeneration else {
                    break
                }
                handle(event)
            }

            guard !Task.isCancelled, generation == monitoringGeneration else {
                return
            }
            isMonitoring = false
            listeningWindowTask?.cancel()
            listeningWindowTask = nil
            if availability == .unknown {
                availability = .fallbackRequired
            }
        }

        listeningWindowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: reducer.policy.listeningWindow)
            guard !Task.isCancelled, generation == monitoringGeneration else {
                return
            }
            expireListeningWindow()
        }
    }

    private func stopMonitoring() {
        monitoringGeneration += 1
        consumeTask?.cancel()
        consumeTask = nil
        listeningWindowTask?.cancel()
        listeningWindowTask = nil
        service.stop()
        isMonitoring = false
    }

    private func expireListeningWindow() {
        listeningWindowExpired = true
        monitoringGeneration += 1
        consumeTask?.cancel()
        consumeTask = nil
        listeningWindowTask = nil
        service.stop()
        isMonitoring = false
    }

    private func handle(_ event: TemporalShakeServiceEvent) {
        switch event {
        case let .availability(availability):
            self.availability = availability

        case let .systemShakeEnded(timestamp):
            publishIfDetected(
                reducer.reduce(.systemShakeEnded(timestamp: timestamp))
            )

        case let .sample(sample):
            publishIfDetected(reducer.reduce(.sample(sample)))
        }
    }

    private func publishIfDetected(_ detection: TemporalShakeDetection?) {
        guard let detection else { return }
        latestEvent = .advanceBranch(
            source: detection.source,
            timestamp: detection.timestamp
        )
    }
}

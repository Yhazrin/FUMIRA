import Foundation
import Observation

/// Result-scoped coordinator for microphone level input.
///
/// Only aggregate dB samples enter this model. It owns no recording and keeps
/// the pure `BlowRevealEngine` as the single source for gust and progress.
@MainActor
@Observable
final class BlowRevealModel {
    private let service: any BlowInputProviding
    private let clock: @Sendable () -> TimeInterval
    private var engine: BlowRevealEngine
    private var consumeTask: Task<Void, Never>?
    private var decayTask: Task<Void, Never>?
    private var lastLevelTimestamp: TimeInterval?

    private(set) var snapshot: BlowRevealSnapshot
    private(set) var availability: BlowInputAvailability = .unknown
    private(set) var isActive = false

    var fallbackRecommended: Bool {
        if case .fallbackRequired = availability {
            return true
        }
        return false
    }

    init(
        service: any BlowInputProviding,
        policy: BlowRevealPolicy = .standard,
        clock: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.service = service
        self.clock = clock
        let engine = BlowRevealEngine(policy: policy)
        self.engine = engine
        snapshot = engine.snapshot
    }

    func activate() {
        guard !isActive, !snapshot.isRevealed else { return }

        resetState(stoppingService: false)
        let stream = service.events()
        isActive = true
        service.start()

        consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in stream {
                guard !Task.isCancelled, isActive else { break }
                handle(event)
            }
        }

        decayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, isActive {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, isActive else { break }
                let now = clock()
                if now - (lastLevelTimestamp ?? now) >= 0.08 {
                    engine.advance(to: now)
                    publishSnapshot()
                }
            }
        }
    }

    func deactivate() {
        guard isActive || consumeTask != nil || decayTask != nil else { return }
        isActive = false
        consumeTask?.cancel()
        consumeTask = nil
        decayTask?.cancel()
        decayTask = nil
        service.stop()
        lastLevelTimestamp = nil
    }

    func reset() {
        deactivate()
        resetState(stoppingService: false)
    }

    private func resetState(stoppingService: Bool) {
        if stoppingService {
            service.stop()
        }
        engine.reset(at: clock())
        snapshot = engine.snapshot
        availability = .unknown
        lastLevelTimestamp = nil
    }

    private func handle(_ event: BlowInputEvent) {
        switch event {
        case let .availability(availability):
            self.availability = availability
            if case .fallbackRequired = availability {
                deactivate()
            }

        case let .level(sample):
            lastLevelTimestamp = sample.timestamp
            engine.ingest(decibels: sample.decibels, at: sample.timestamp)
            publishSnapshot()
        }
    }

    private func publishSnapshot() {
        let next = engine.snapshot
        guard next != snapshot else { return }
        snapshot = next
        if next.isRevealed {
            deactivate()
        }
    }
}

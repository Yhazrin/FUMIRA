import Foundation

enum TemporalShakeTriggerSource: Equatable, Sendable {
    case deviceResponder
    case externalSample
    case fallbackButton
}

struct TemporalShakeDetection: Equatable, Sendable {
    let source: TemporalShakeTriggerSource
    let timestamp: TimeInterval
}

enum TemporalShakeDetectorInput: Equatable, Sendable {
    case systemShakeEnded(timestamp: TimeInterval)
    case sample(TemporalShakeSample)
    case fallbackRequested(timestamp: TimeInterval)

    var timestamp: TimeInterval {
        switch self {
        case let .systemShakeEnded(timestamp), let .fallbackRequested(timestamp):
            timestamp
        case let .sample(sample):
            sample.timestamp
        }
    }
}

struct TemporalShakeDetectionPolicy: Equatable, Sendable {
    let triggerThreshold: Double
    let releaseThreshold: Double
    let debounceInterval: TimeInterval
    let listeningWindow: Duration

    static let standard = TemporalShakeDetectionPolicy(
        triggerThreshold: 0.82,
        releaseThreshold: 0.34,
        debounceInterval: 1.2,
        listeningWindow: .seconds(8)
    )

    init(
        triggerThreshold: Double,
        releaseThreshold: Double,
        debounceInterval: TimeInterval,
        listeningWindow: Duration = .seconds(8)
    ) {
        let safeTrigger = triggerThreshold.isFinite
            ? max(triggerThreshold, 0.001)
            : 0.82
        self.triggerThreshold = safeTrigger
        self.releaseThreshold = releaseThreshold.isFinite
            ? min(max(releaseThreshold, 0), safeTrigger)
            : min(0.34, safeTrigger)
        self.debounceInterval = debounceInterval.isFinite
            ? max(debounceInterval, 0)
            : 1.2
        self.listeningWindow = max(listeningWindow, .milliseconds(250))
    }
}

/// Deterministic shake detector for mock/external samples and discrete UIKit
/// shake events. Sustained high input can fire only once until it drops below
/// the release threshold. All sources share one debounce clock.
struct TemporalShakeReducer: Sendable {
    let policy: TemporalShakeDetectionPolicy

    private(set) var isArmed = true
    private var latestTimestamp: TimeInterval?
    private var lastTriggerTimestamp: TimeInterval?

    init(policy: TemporalShakeDetectionPolicy = .standard) {
        self.policy = policy
    }

    mutating func reduce(
        _ input: TemporalShakeDetectorInput
    ) -> TemporalShakeDetection? {
        let timestamp = input.timestamp
        guard timestamp.isFinite else { return nil }
        if case let .sample(sample) = input {
            // Invalid samples must not advance the reducer clock; otherwise a
            // corrupt future timestamp could suppress every later input.
            guard sample.intensity.isFinite else { return nil }
        }
        guard timestamp >= (latestTimestamp ?? timestamp) else { return nil }
        latestTimestamp = timestamp

        switch input {
        case .systemShakeEnded:
            return accept(source: .deviceResponder, at: timestamp)

        case let .sample(sample):
            let intensity = abs(sample.intensity)
            if intensity <= policy.releaseThreshold {
                isArmed = true
                return nil
            }
            guard intensity >= policy.triggerThreshold, isArmed else {
                return nil
            }
            // A threshold crossing is consumed even when the shared debounce
            // rejects it. Another crossing requires a genuine release first.
            isArmed = false
            return accept(source: .externalSample, at: timestamp)

        case .fallbackRequested:
            return accept(source: .fallbackButton, at: timestamp)
        }
    }

    mutating func reset() {
        isArmed = true
        latestTimestamp = nil
        lastTriggerTimestamp = nil
    }

    private mutating func accept(
        source: TemporalShakeTriggerSource,
        at timestamp: TimeInterval
    ) -> TemporalShakeDetection? {
        if let lastTriggerTimestamp,
           timestamp - lastTriggerTimestamp < policy.debounceInterval {
            return nil
        }
        lastTriggerTimestamp = timestamp
        return TemporalShakeDetection(source: source, timestamp: timestamp)
    }
}

import Foundation

struct BlowRevealPolicy: Equatable, Sendable {
    let noiseGateDecibels: Double
    let fullGustDecibels: Double
    let attackTimeConstant: TimeInterval
    let releaseTimeConstant: TimeInterval
    let revealGainPerSecond: Double
    let revealDecayPerSecond: Double
    let activeGustThreshold: Double

    static let standard = BlowRevealPolicy(
        noiseGateDecibels: -38,
        fullGustDecibels: -12,
        attackTimeConstant: 0.08,
        releaseTimeConstant: 0.22,
        revealGainPerSecond: 0.72,
        revealDecayPerSecond: 0.10,
        activeGustThreshold: 0.12
    )

    init(
        noiseGateDecibels: Double,
        fullGustDecibels: Double,
        attackTimeConstant: TimeInterval,
        releaseTimeConstant: TimeInterval,
        revealGainPerSecond: Double,
        revealDecayPerSecond: Double,
        activeGustThreshold: Double
    ) {
        let gate = noiseGateDecibels.isFinite ? noiseGateDecibels : -38
        let requestedFull = fullGustDecibels.isFinite ? fullGustDecibels : -12
        self.noiseGateDecibels = min(max(gate, -120), -1)
        self.fullGustDecibels = min(
            max(requestedFull, self.noiseGateDecibels + 1),
            0
        )
        self.attackTimeConstant = Self.positiveFinite(
            attackTimeConstant,
            fallback: 0.08
        )
        self.releaseTimeConstant = Self.positiveFinite(
            releaseTimeConstant,
            fallback: 0.22
        )
        self.revealGainPerSecond = Self.nonnegativeFinite(
            revealGainPerSecond,
            fallback: 0.72
        )
        self.revealDecayPerSecond = Self.nonnegativeFinite(
            revealDecayPerSecond,
            fallback: 0.10
        )
        self.activeGustThreshold = min(
            max(activeGustThreshold.isFinite ? activeGustThreshold : 0.12, 0.001),
            1
        )
    }

    func normalizedGust(for decibels: Double) -> Double {
        guard decibels.isFinite else {
            return decibels == .infinity ? 1 : 0
        }
        guard decibels > noiseGateDecibels else { return 0 }
        guard decibels < fullGustDecibels else { return 1 }

        let linear = (decibels - noiseGateDecibels)
            / (fullGustDecibels - noiseGateDecibels)
        // Smoothstep prevents a hard visual jump immediately above the gate.
        return linear * linear * (3 - 2 * linear)
    }

    private static func positiveFinite(
        _ value: Double,
        fallback: Double
    ) -> Double {
        value.isFinite ? max(value, 0.001) : fallback
    }

    private static func nonnegativeFinite(
        _ value: Double,
        fallback: Double
    ) -> Double {
        value.isFinite ? max(value, 0) : fallback
    }
}

struct BlowRevealSnapshot: Equatable, Sendable {
    let rawGust: Double
    let gust: Double
    let revealProgress: Double

    var isRevealed: Bool {
        revealProgress >= 1
    }
}

/// Deterministic dB → gust → reveal state. Callers provide monotonic timestamps;
/// the engine owns no audio APIs, timers, tasks, or process lifecycle state.
struct BlowRevealEngine: Sendable {
    let policy: BlowRevealPolicy

    private(set) var rawGust = 0.0
    private(set) var gust = 0.0
    private(set) var revealProgress = 0.0
    private var lastTimestamp: TimeInterval?

    init(policy: BlowRevealPolicy = .standard) {
        self.policy = policy
    }

    var snapshot: BlowRevealSnapshot {
        BlowRevealSnapshot(
            rawGust: rawGust,
            gust: gust,
            revealProgress: revealProgress
        )
    }

    mutating func reset(at timestamp: TimeInterval) {
        rawGust = 0
        gust = 0
        revealProgress = 0
        lastTimestamp = timestamp.isFinite ? timestamp : 0
    }

    mutating func ingest(decibels: Double, at timestamp: TimeInterval) {
        step(toward: policy.normalizedGust(for: decibels), at: timestamp)
    }

    /// Decays an interrupted gust even when the input service stops publishing.
    mutating func advance(to timestamp: TimeInterval) {
        step(toward: 0, at: timestamp)
    }

    private mutating func step(
        toward targetGust: Double,
        at timestamp: TimeInterval
    ) {
        guard timestamp.isFinite else { return }
        guard let previousTimestamp = lastTimestamp else {
            lastTimestamp = timestamp
            rawGust = min(max(targetGust, 0), 1)
            return
        }
        guard timestamp >= previousTimestamp else { return }

        lastTimestamp = timestamp
        rawGust = min(max(targetGust, 0), 1)
        let elapsed = timestamp - previousTimestamp
        guard elapsed > 0 else { return }

        let timeConstant = rawGust > gust
            ? policy.attackTimeConstant
            : policy.releaseTimeConstant
        let smoothing = 1 - exp(-elapsed / timeConstant)
        gust = min(max(gust + (rawGust - gust) * smoothing, 0), 1)

        guard revealProgress < 1 else {
            revealProgress = 1
            return
        }

        if gust >= policy.activeGustThreshold {
            revealProgress += elapsed * policy.revealGainPerSecond * gust
        } else {
            revealProgress -= elapsed * policy.revealDecayPerSecond
        }
        revealProgress = min(max(revealProgress, 0), 1)
    }
}

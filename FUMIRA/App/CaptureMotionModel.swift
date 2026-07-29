import Foundation
import Observation

@MainActor
@Observable
final class CaptureMotionModel {
    private let service: any CaptureMotionProviding
    private let haptics: any HapticsClient
    private var consumeTask: Task<Void, Never>?
    private var recentSamples: [CaptureMotionSample] = []
    private var stableSince: TimeInterval?
    private var didPlayAnchorHaptic = false

    private(set) var isActive = false
    private(set) var stability = 0.0
    private(set) var anchorProgress = 0.0
    private(set) var isAnchored = false
    private(set) var roll = 0.0
    private(set) var pitch = 0.0
    private(set) var yaw = 0.0
    private var anchorFeedbackEnabled = true

    init(
        service: any CaptureMotionProviding,
        haptics: any HapticsClient
    ) {
        self.service = service
        self.haptics = haptics
    }

    func activate() {
        guard !isActive else { return }
        resetState()
        isActive = true
        consumeTask = Task { [weak self] in
            guard let self else { return }
            let stream = service.samples()
            await service.start()
            for await sample in stream {
                guard !Task.isCancelled else { break }
                ingest(sample)
            }
            await service.stop()
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        consumeTask?.cancel()
        consumeTask = nil
        Task {
            await service.stop()
        }
    }

    func makeContext() -> TemporalMotionContext {
        TemporalMotionContext(
            samples: recentSamples,
            stabilityAtShutter: stability,
            wasAnchored: isAnchored
        )
    }

    func setAnchorFeedbackEnabled(_ isEnabled: Bool) {
        anchorFeedbackEnabled = isEnabled
    }

    private func ingest(_ sample: CaptureMotionSample) {
        let smoothing = 0.2
        stability += (sample.stability - stability) * smoothing
        roll += (sample.roll - roll) * smoothing
        pitch += (sample.pitch - pitch) * smoothing
        yaw += (sample.yaw - yaw) * smoothing

        recentSamples.append(sample)
        let cutoff = sample.timestamp - 1.2
        recentSamples.removeAll { $0.timestamp < cutoff }

        if stability >= 0.82 {
            stableSince = stableSince ?? sample.timestamp
            let duration = max(0, sample.timestamp - (stableSince ?? sample.timestamp))
            anchorProgress = min(duration / 0.42, 1)
        } else if stability < 0.68 {
            stableSince = nil
            anchorProgress = max(0, anchorProgress - 0.16)
            isAnchored = false
            didPlayAnchorHaptic = false
        }

        if anchorProgress >= 1 {
            isAnchored = true
            if anchorFeedbackEnabled, !didPlayAnchorHaptic {
                didPlayAnchorHaptic = true
                haptics.play(.timeAnchor)
            }
        }
    }

    private func resetState() {
        stability = 0
        anchorProgress = 0
        isAnchored = false
        roll = 0
        pitch = 0
        yaw = 0
        recentSamples = []
        stableSince = nil
        didPlayAnchorHaptic = false
    }
}

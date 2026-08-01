import Foundation
import UIKit

/// UIDevice's public proximity-monitoring API is binary: it reports near/far,
/// never a physical distance. Exposure progress is therefore derived from time
/// in `TemporalDarkroomEngine`, not from a fabricated distance estimate.
@MainActor
final class DeviceTemporalDarkroomService: NSObject, TemporalDarkroomProviding {
    private let device: UIDevice
    private let notificationCenter: NotificationCenter
    private let clock: @Sendable () -> TimeInterval
    private var continuation: AsyncStream<TemporalDarkroomEvent>.Continuation?
    private var isStarted = false
    private var isMonitoringProximity = false

    init(
        device: UIDevice = .current,
        notificationCenter: NotificationCenter = .default,
        clock: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.device = device
        self.notificationCenter = notificationCenter
        self.clock = clock
        super.init()
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

#if targetEnvironment(simulator)
        continuation?.yield(.availability(.alternativeInputRequired))
#else
        device.isProximityMonitoringEnabled = true
        guard device.isProximityMonitoringEnabled else {
            continuation?.yield(.availability(.alternativeInputRequired))
            return
        }

        isMonitoringProximity = true
        notificationCenter.addObserver(
            self,
            selector: #selector(proximityStateDidChange),
            name: UIDevice.proximityStateDidChangeNotification,
            object: device
        )
        continuation?.yield(.availability(.proximitySensor))
        emitSensorState()
#endif
    }

    func stop() {
        guard isStarted || continuation != nil else { return }
        isStarted = false

        if isMonitoringProximity {
            notificationCenter.removeObserver(
                self,
                name: UIDevice.proximityStateDidChangeNotification,
                object: device
            )
            device.isProximityMonitoringEnabled = false
            isMonitoringProximity = false
        }

        continuation?.finish()
        continuation = nil
    }

    func setAlternativeInputActive(_ isActive: Bool, timestamp: TimeInterval) {
        guard isStarted else { return }
        continuation?.yield(
            .observation(
                TemporalDarkroomObservation(
                    state: isActive ? .near : .far,
                    source: .alternative,
                    timestamp: timestamp
                )
            )
        )
    }

    @objc
    nonisolated private func proximityStateDidChange() {
        Task { @MainActor [weak self] in
            self?.emitSensorState()
        }
    }

    private func emitSensorState() {
        guard isStarted, isMonitoringProximity else { return }
        continuation?.yield(
            .observation(
                TemporalDarkroomObservation(
                    state: device.proximityState ? .near : .far,
                    source: .proximitySensor,
                    timestamp: clock()
                )
            )
        )
    }
}

import CoreHaptics
import UIKit

/// Semantic haptics for the camera experience.
///
/// Core Haptics cannot steer a physical "x axis". The paired transients below
/// vary intensity and sharpness over time to create the illusion of a lateral
/// detent, shutter blade, or developing photograph.
@MainActor
final class LiveHapticsClient: HapticsClient {
    private var engine: CHHapticEngine?
    private var isEngineRunning = false
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    init() {
        prepareEngine()
    }

    func play(_ event: HapticEvent) {
        guard supportsHaptics else {
            playUIKitFallback(event)
            return
        }

        guard let engine = engine ?? makeEngine() else {
            playUIKitFallback(event)
            return
        }

        do {
            if !isEngineRunning {
                try engine.start()
                isEngineRunning = true
            }
            let player = try engine.makePlayer(with: pattern(for: event))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            isEngineRunning = false
            prepareEngine()
            playUIKitFallback(event)
        }
    }

    private func prepareEngine() {
        guard supportsHaptics, let engine = engine ?? makeEngine() else { return }
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
        }
    }

    private func makeEngine() -> CHHapticEngine? {
        do {
            let newEngine = try CHHapticEngine()
            newEngine.isAutoShutdownEnabled = true
            newEngine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.isEngineRunning = false
                }
            }
            newEngine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.isEngineRunning = false
                    self?.prepareEngine()
                }
            }
            engine = newEngine
            return newEngine
        } catch {
            return nil
        }
    }

    private func pattern(for event: HapticEvent) throws -> CHHapticPattern {
        let events: [CHHapticEvent]

        switch event {
        case .selection:
            events = [transient(time: 0, intensity: 0.22, sharpness: 0.72)]

        case .timeDetent:
            // Hard leading tooth plus a very short body return: crisp, but not noisy.
            events = [
                transient(time: 0, intensity: 0.46, sharpness: 0.98),
                transient(time: 0.027, intensity: 0.16, sharpness: 0.38)
            ]

        case .timeAnchor:
            // Soft leading click + crisp trailing click reads like a lateral notch.
            events = [
                transient(time: 0, intensity: 0.54, sharpness: 0.22),
                transient(time: 0.038, intensity: 0.68, sharpness: 0.98)
            ]

        case .shutterPress:
            // One dry, high-sharpness contact at the bottom of the short travel.
            events = [transient(time: 0, intensity: 0.40, sharpness: 1)]

        case .shutter:
            // A crisp release and immediate return, without a lingering motor rumble.
            events = [
                transient(time: 0, intensity: 0.92, sharpness: 1),
                transient(time: 0.032, intensity: 0.44, sharpness: 0.82)
            ]

        case .reveal:
            // A developing swell that resolves into a clean final click.
            events = [
                continuous(
                    time: 0,
                    duration: 0.22,
                    intensity: 0.16,
                    sharpness: 0.18
                ),
                transient(time: 0.22, intensity: 0.7, sharpness: 0.88)
            ]

        case .save:
            // Three restrained "film advance" teeth.
            events = [
                transient(time: 0, intensity: 0.28, sharpness: 0.9),
                transient(time: 0.055, intensity: 0.36, sharpness: 0.78),
                transient(time: 0.11, intensity: 0.52, sharpness: 0.62)
            ]

        case .success:
            events = [
                transient(time: 0, intensity: 0.35, sharpness: 0.48),
                transient(time: 0.09, intensity: 0.5, sharpness: 0.7)
            ]
        }

        return try CHHapticPattern(events: events, parameters: [])
    }

    private func transient(
        time: TimeInterval,
        intensity: Float,
        sharpness: Float
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func continuous(
        time: TimeInterval,
        duration: TimeInterval,
        intensity: Float,
        sharpness: Float
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func playUIKitFallback(_ event: HapticEvent) {
        switch event {
        case .selection, .timeDetent:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()

        case .timeAnchor:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.7)

        case .shutterPress:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.45)

        case .shutter:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 1)

        case .save:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred(intensity: 0.75)

        case .reveal, .success:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }
}

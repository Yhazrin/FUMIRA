import CoreMotion
import Foundation

/// Functional capture sampling. This is separate from MotionFieldProviding,
/// whose samples remain purely decorative outside the viewfinder.
final class CoreCaptureMotionService: CaptureMotionProviding, @unchecked Sendable {
    private let manager = CMMotionManager()
    private let state = CaptureMotionStreamState()

    func samples() -> AsyncStream<CaptureMotionSample> {
        AsyncStream { continuation in
            Task {
                await state.install(continuation)
            }
        }
    }

    func start() async {
        guard await state.beginIfNeeded() else { return }
        guard manager.isDeviceMotionAvailable else {
            await state.end()
            return
        }

        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let rotationRate = Self.magnitude(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z
            )
            let acceleration = Self.magnitude(
                x: motion.userAcceleration.x,
                y: motion.userAcceleration.y,
                z: motion.userAcceleration.z
            )
            let instability = min(
                1,
                (rotationRate / 1.35) * 0.72 + (acceleration / 0.22) * 0.28
            )
            let sample = CaptureMotionSample(
                timestamp: motion.timestamp,
                roll: motion.attitude.roll,
                pitch: motion.attitude.pitch,
                yaw: motion.attitude.yaw,
                rotationRate: rotationRate,
                acceleration: acceleration,
                stability: max(0, 1 - instability)
            )

            Task {
                await self.state.yield(sample)
            }
        }
    }

    func stop() async {
        manager.stopDeviceMotionUpdates()
        await state.end()
    }

    private static func magnitude(x: Double, y: Double, z: Double) -> Double {
        sqrt(x * x + y * y + z * z)
    }
}

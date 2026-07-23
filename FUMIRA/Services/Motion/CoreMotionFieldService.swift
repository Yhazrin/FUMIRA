import CoreMotion
import Foundation

final class CoreMotionFieldService: MotionFieldProviding, @unchecked Sendable {
    private let manager = CMMotionManager()
    private let state = MotionFieldServiceState()
    private var baselineX: Double?
    private var baselineY: Double?
    private var filteredRoll = 0.0
    private var filteredPitch = 0.0

    func samples() -> AsyncStream<MotionFieldSample> {
        AsyncStream { continuation in
            Task {
                await state.setContinuation(continuation)
            }
        }
    }

    func start() async {
        let shouldStart = await state.beginIfNeeded()
        guard shouldStart else { return }
        guard manager.isDeviceMotionAvailable else {
            await state.end()
            return
        }

        manager.deviceMotionUpdateInterval = 1.0 / 25.0
        baselineX = nil
        baselineY = nil
        filteredRoll = 0
        filteredPitch = 0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravityX = motion.gravity.x
            let gravityY = motion.gravity.y
            if self.baselineX == nil || self.baselineY == nil {
                self.baselineX = gravityX
                self.baselineY = gravityY
                return
            }
            let rollTarget = Self.normalizedDelta(gravityX - (self.baselineX ?? gravityX))
            let pitchTarget = Self.normalizedDelta(gravityY - (self.baselineY ?? gravityY))
            self.filteredRoll += (rollTarget - self.filteredRoll) * 0.18
            self.filteredPitch += (pitchTarget - self.filteredPitch) * 0.18
            let roll = self.filteredRoll
            let pitch = self.filteredPitch
            Task {
                let running = await self.state.running
                guard running else { return }
                await self.state.yield(MotionFieldSample(roll: roll, pitch: pitch))
            }
        }
    }

    func stop() async {
        manager.stopDeviceMotionUpdates()
        await state.end()
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    private static func normalizedDelta(_ value: Double) -> Double {
        let deadZone = 0.012
        guard abs(value) > deadZone else { return 0 }
        let signed = value < 0 ? -1.0 : 1.0
        let adjusted = max(0, abs(value) - deadZone)
        return clamp(signed * adjusted / 0.16)
    }
}

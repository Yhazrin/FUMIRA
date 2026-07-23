import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MotionFieldModel {
    private let service: any MotionFieldProviding
    private var consumeTask: Task<Void, Never>?

    var roll: Double = 0
    var pitch: Double = 0
    private(set) var isActive = false

    init(service: any MotionFieldProviding) {
        self.service = service
    }

    func activate(reduceMotion: Bool, lowPowerMode: Bool) {
        guard !reduceMotion, !lowPowerMode else {
            deactivate()
            return
        }
        guard !isActive else { return }
        isActive = true

        consumeTask?.cancel()
        consumeTask = Task { [weak self] in
            guard let self else { return }
            let stream = service.samples()
            await service.start()
            for await sample in stream {
                guard !Task.isCancelled else { break }
                roll = sample.roll
                pitch = sample.pitch
            }
            await service.stop()
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        consumeTask?.cancel()
        consumeTask = nil
        roll = 0
        pitch = 0
        Task {
            await service.stop()
        }
    }

    func offset(for depth: FlatMotionLayerDepth) -> CGSize {
        guard isActive else { return .zero }
        let magnitude = depth.parallaxPoints
        return CGSize(
            width: roll * magnitude,
            height: -pitch * magnitude * 0.65
        )
    }

    func decorationRotation() -> Angle {
        guard isActive else { return .zero }
        return .degrees(roll * FlatMotionParallax.maxRotationDegrees)
    }
}

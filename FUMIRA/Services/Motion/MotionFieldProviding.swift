import Foundation

struct MotionFieldSample: Sendable, Equatable {
    var roll: Double
    var pitch: Double

    static let zero = MotionFieldSample(roll: 0, pitch: 0)
}

protocol MotionFieldProviding: Sendable {
    func samples() -> AsyncStream<MotionFieldSample>
    func start() async
    func stop() async
}

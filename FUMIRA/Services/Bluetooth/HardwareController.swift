import Foundation

struct HardwareSnapshot: Equatable, Sendable {
    let name: String
    let batteryLevel: Int
}

enum HardwareEvent: Sendable {
    case shutterPressed
    case rotaryDelta(Double)
    case disconnected
}

protocol HardwareController: Sendable {
    func connect() async throws -> HardwareSnapshot
    func disconnect() async
    func events() async -> AsyncStream<HardwareEvent>
}

actor MockHardwareController: HardwareController {
    func connect() async throws -> HardwareSnapshot {
        HardwareSnapshot(name: "FutureCam_01", batteryLevel: 86)
    }

    func disconnect() async {}

    func events() async -> AsyncStream<HardwareEvent> {
        AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}

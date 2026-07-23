import Foundation

enum HapticEvent: Sendable {
    case selection
    case shutter
    case success
}

@MainActor
protocol HapticsClient: AnyObject {
    func play(_ event: HapticEvent)
}

@MainActor
final class MockHapticsClient: HapticsClient {
    func play(_ event: HapticEvent) {}
}

import Foundation

enum HapticEvent: Sendable {
    case selection
    case timeDetent
    case timeAnchor
    case shutterPress
    case shutter
    case reveal
    case save
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

import Foundation

enum AppPhase: Equatable, Sendable {
    case connection
    case bluetoothPermission
    case connected
    case cameraPermission
    case viewfinder
    case shuttered
    case generating
    case understanding
    case storyWriting
    case result
    case share
    case pipelineFailure
    case disconnected
}

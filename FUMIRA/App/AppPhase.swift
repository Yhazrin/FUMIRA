import Foundation

enum AppPhase: Equatable, Sendable {
    case connection
    case bluetoothPermission
    case connected
    case cameraPermission
    case viewfinder
    case shuttered
    case understanding
    case storyWriting
    case storyReady
    case generating
    case result
    case share
    case pipelineFailure
    case disconnected
}

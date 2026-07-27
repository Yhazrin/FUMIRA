import ActivityKit
import Foundation

struct CameraLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case framing
            case capturing
            case captured
        }

        var phase: Phase
        var targetLabel: String
        var zoomLabel: String
        var flashSymbol: String
        var lensSymbol: String
        var isGridEnabled: Bool
        var aspectRatioLabel: String
    }

    var cameraName: String
}

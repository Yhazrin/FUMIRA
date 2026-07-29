import ActivityKit
import Foundation

struct CameraLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case framing
            case capturing
            case captured
            case understanding
            case storyWriting
            case generating
            case ready
            case failed
        }

        var phase: Phase
        var targetLabel: String
        var zoomLabel: String
        var flashSymbol: String
        var lensSymbol: String
        var isGridEnabled: Bool
        var aspectRatioLabel: String
        /// Optional for payload compatibility with camera-only activities.
        /// Processing stages clamp it to 0...1 before rendering.
        var progress: Double? = nil

        var normalizedProgress: Double {
            min(max(progress ?? 0, 0), 1)
        }

        var isCameraPhase: Bool {
            switch phase {
            case .framing, .capturing, .captured:
                true
            case .understanding, .storyWriting, .generating, .ready, .failed:
                false
            }
        }

        var isProcessing: Bool {
            switch phase {
            case .understanding, .storyWriting, .generating:
                true
            case .framing, .capturing, .captured, .ready, .failed:
                false
            }
        }
    }

    var cameraName: String
}

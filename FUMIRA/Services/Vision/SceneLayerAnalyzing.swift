import Foundation

protocol SceneLayerAnalyzing: Sendable {
    func analyze(photo: CapturedPhoto) async -> TemporalVisualContext
}

import Foundation

actor MockSceneLayerAnalyzer: SceneLayerAnalyzing {
    func analyze(photo: CapturedPhoto) async -> TemporalVisualContext {
        TemporalVisualContext(
            foregroundMaskPNG: nil,
            salientRegions: [
                TemporalSalientRegion(
                    normalizedX: 0.12,
                    normalizedY: 0.28,
                    normalizedWidth: 0.34,
                    normalizedHeight: 0.48
                ),
                TemporalSalientRegion(
                    normalizedX: 0.52,
                    normalizedY: 0.24,
                    normalizedWidth: 0.32,
                    normalizedHeight: 0.54
                ),
            ]
        )
    }
}

import SwiftUI

protocol CameraPreviewFactory: Sendable {
    var isLive: Bool { get }

    @MainActor
    func makePreview() -> AnyView
}

struct MockCameraPreviewFactory: CameraPreviewFactory {
    let isLive = false

    @MainActor
    func makePreview() -> AnyView {
        AnyView(
            TemporalParkScene(time: .now, cornerRadius: 0)
                // Match a portrait 4:3 camera sensor. The viewfinder clips this
                // one stable scene into each card instead of asking the scene
                // to re-layout trees and roads for every pinch stop.
                .aspectRatio(3.0 / 4.0, contentMode: .fill)
        )
    }
}

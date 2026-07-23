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
        )
    }
}

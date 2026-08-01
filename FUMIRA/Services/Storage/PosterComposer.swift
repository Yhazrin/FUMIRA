import SwiftUI
import UIKit

/// Renders the flat poster card into PNG bytes via `ImageRenderer`.
/// Uses DesignSystem tokens only — no blue-purple AI gradients.
enum PosterComposer {
    static let exportWidth: CGFloat = 390
    static let exportHeight: CGFloat = 640

    @MainActor
    static func renderPNG(
        time: TimePosition,
        yearLabel: String,
        title: String,
        narrative: String,
        sceneImageData: Data?,
        interpretationTrace: TemporalInterpretationTrace? = nil
    ) throws -> Data {
        let sceneImage = sceneImageData.flatMap(UIImage.init(data:))
        let content = PosterExportCard(
            time: time,
            yearLabel: yearLabel,
            title: title,
            narrative: narrative,
            sceneImage: sceneImage,
            interpretationTrace: interpretationTrace
        )
        .frame(width: exportWidth, height: exportHeight)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData(), !data.isEmpty else {
            throw PosterStorageError.encodeFailed
        }
        return data
    }

    static func yearLabel(for time: TimePosition) -> String {
        time.compactLabel
    }
}

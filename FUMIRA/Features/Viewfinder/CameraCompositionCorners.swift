import SwiftUI

/// Four white focus brackets following the camera crop's exact contour.
///
/// The stroke sits fully outside the crop. Its inner edge shares the crop's
/// continuous rounded-rectangle path, so the brackets remain flush while the
/// composition frame animates between aspect ratios.
struct CameraCompositionCorners: View {
    let frame: CGRect
    let cornerRadius: CGFloat
    var lineWidth: CGFloat = 3
    var color: Color = PosterPalette.paperWhite

    private var canvasPadding: CGFloat { lineWidth + 1 }

    var body: some View {
        Canvas { context, size in
            let cropRect = CGRect(
                x: canvasPadding,
                y: canvasPadding,
                width: max(size.width - canvasPadding * 2, 1),
                height: max(size.height - canvasPadding * 2, 1)
            )
            let halfLineWidth = lineWidth / 2
            let outlineRect = cropRect.insetBy(
                dx: -halfLineWidth,
                dy: -halfLineWidth
            )
            let outline = RoundedRectangle(
                cornerRadius: cornerRadius + halfLineWidth,
                style: .continuous
            )
            .path(in: outlineRect)

            for region in cornerRegions(for: outlineRect) {
                context.drawLayer { layer in
                    var clip = Path()
                    clip.addRect(region)
                    layer.clip(to: clip)
                    layer.stroke(
                        outline,
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
        .frame(
            width: frame.width + canvasPadding * 2,
            height: frame.height + canvasPadding * 2
        )
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.28),
            value: frame
        )
    }

    private func cornerRegions(for rect: CGRect) -> [CGRect] {
        let extent = min(
            max(
                cornerRadius + min(frame.width, frame.height) * 0.1,
                cornerRadius + 28
            ),
            min(frame.width, frame.height) * 0.3
        )

        return [
            CGRect(
                x: rect.minX - lineWidth,
                y: rect.minY - lineWidth,
                width: extent + lineWidth,
                height: extent + lineWidth
            ),
            CGRect(
                x: rect.maxX - extent,
                y: rect.minY - lineWidth,
                width: extent + lineWidth,
                height: extent + lineWidth
            ),
            CGRect(
                x: rect.maxX - extent,
                y: rect.maxY - extent,
                width: extent + lineWidth,
                height: extent + lineWidth
            ),
            CGRect(
                x: rect.minX - lineWidth,
                y: rect.maxY - extent,
                width: extent + lineWidth,
                height: extent + lineWidth
            )
        ]
    }
}

#Preview("Outer brackets on photo") {
    ZStack {
        LinearGradient(
            colors: [Color.gray.opacity(0.7), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        CameraCompositionCorners(
            frame: CGRect(x: 60, y: 60, width: 200, height: 280),
            cornerRadius: 18
        )
    }
    .frame(width: 320, height: 400)
}

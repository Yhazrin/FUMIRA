import SwiftUI
import UIKit

struct CapturedPhotoView: View {
    let photo: CapturedPhoto?
    /// Prefer a pre-decoded image from ``AppModel`` — never decode in hot paths.
    var decodedImage: UIImage? = nil
    var cornerRadius: CGFloat = PosterRadius.card

    private var displayAspectRatio: CGFloat {
        if let ratio = photo?.displayAspectRatio {
            return CGFloat(ratio)
        }
        if let image = resolvedImage, image.size.height > 0 {
            return image.size.width / image.size.height
        }
        return 3.0 / 4.0
    }

    private var resolvedImage: UIImage? {
        if let decodedImage { return decodedImage }
        // Fallback for previews / non-pipeline call sites only.
        guard let photo else { return nil }
        return UIImage(data: photo.data)
    }

    var body: some View {
        PhotoAspectContainer(aspectRatio: displayAspectRatio) {
            ZStack {
                PosterPalette.ink.opacity(0.08)

                if let image = resolvedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("刚刚拍下的原始照片")
                } else {
                    TemporalParkScene(time: .now, cornerRadius: cornerRadius)
                        .accessibilityLabel("原始照片占位画面")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Gives a photo-stage an exact ratio at layout time instead of relying on
/// `frame(maxHeight:)`. GeometryReader-based overlays otherwise greedily take
/// the maximum height and merely center the correctly-shaped photo inside it,
/// leaving a large invisible gap around landscape captures.
struct PhotoAspectContainer<Content: View>: View {
    let aspectRatio: CGFloat
    var maximumHeight: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        PhotoAspectLayout(
            aspectRatio: aspectRatio,
            maximumHeight: maximumHeight
        ) {
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PhotoAspectLayout: Layout {
    let aspectRatio: CGFloat
    let maximumHeight: CGFloat?

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        fittedSize(in: proposal)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        // Always place an aspect-correct rect. Parents may expand us with
        // `frame(maxWidth: .infinity)` for centering — filling those bounds
        // would silently squash 3:4 / 9:16 into a near-square hero slot.
        let size = fittedSize(
            in: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
    }

    private func fittedSize(in proposal: ProposedViewSize) -> CGSize {
        let ratio = max(aspectRatio, 0.01)
        let fallback = maximumHeight.map { $0 * ratio } ?? 320
        var width = max(0, proposal.width ?? fallback)
        var height = width / ratio

        if let maximumHeight, height > maximumHeight {
            height = maximumHeight
            width = height * ratio
        }
        if let proposedHeight = proposal.height, height > proposedHeight {
            height = proposedHeight
            width = height * ratio
        }

        return CGSize(width: width, height: height)
    }
}

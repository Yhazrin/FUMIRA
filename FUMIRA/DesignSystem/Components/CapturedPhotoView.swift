import SwiftUI
import UIKit

struct CapturedPhotoView: View {
    let photo: CapturedPhoto?
    var cornerRadius: CGFloat = PosterRadius.card

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let photo, let image = UIImage(data: photo.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityLabel("刚刚拍下的原始照片")
                } else {
                    TemporalParkScene(time: .now, cornerRadius: cornerRadius)
                        .accessibilityLabel("原始照片占位画面")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

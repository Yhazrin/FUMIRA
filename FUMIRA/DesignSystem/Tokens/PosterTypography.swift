import SwiftUI

enum PosterTypography {
    static let immersiveCameraTitleSize: CGFloat = 38

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("LXGWMarkerGothic-Regular", size: size, relativeTo: style)
    }

    static func script(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("CaveatBrush-Regular", size: size, relativeTo: style)
    }
}

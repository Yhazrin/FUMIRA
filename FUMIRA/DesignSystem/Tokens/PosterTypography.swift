import CoreText
import SwiftUI
import UIKit

enum PosterTypography {
    /// Clay OS 字体 — SF Pro Rounded 主要语言，等宽用于时间值和终端状态。
    static let screenTitle = ClayTypography.displaySmall
    static let sectionTitle = ClayTypography.subheading
    static let cardTitle = ClayTypography.heading
    static let metric = ClayTypography.displaySmall
    static let body = ClayTypography.body
    static let supporting = ClayTypography.bodySmall
    static let label = ClayTypography.label
    static let caption = ClayTypography.labelSmall
    static let button = ClayTypography.bodyBold

    /// 品牌标识
    static let wordmark = script(68)
    static let accent = ClayTypography.heading
    static let handwrittenTitle = display(26)

    /// 固定尺寸用于海报导出
    static func display(_ size: CGFloat) -> Font {
        _ = BundledFonts.registration
        if BundledFonts.markerGothicAvailable {
            return .custom(BundledFonts.markerGothicName, size: size)
        }
        return .system(size: size, weight: .bold, design: .rounded)
    }

    static func script(_ size: CGFloat) -> Font {
        _ = BundledFonts.registration
        if BundledFonts.caveatBrushAvailable {
            return .custom(BundledFonts.caveatBrushName, size: size)
        }
        return .system(size: size, weight: .bold, design: .rounded)
    }
}

private enum BundledFonts {
    static let caveatBrushName = "CaveatBrush-Regular"
    static let markerGothicName = "LXGWMarkerGothic-Regular"

    static let registration: Void = {
        register(resource: caveatBrushName, subdirectory: "Fonts/CaveatBrush")
        register(resource: caveatBrushName, subdirectory: nil)
        register(resource: markerGothicName, subdirectory: "Fonts/LXGWMarkerGothic")
        register(resource: markerGothicName, subdirectory: nil)
    }()

    static var caveatBrushAvailable: Bool {
        UIFont(name: caveatBrushName, size: 12) != nil
    }

    static var markerGothicAvailable: Bool {
        UIFont(name: markerGothicName, size: 12) != nil
    }

    private static func register(resource: String, subdirectory: String?) {
        let url = Bundle.main.url(
            forResource: resource,
            withExtension: "ttf",
            subdirectory: subdirectory
        ) ?? Bundle.main.url(forResource: resource, withExtension: "ttf")
        guard let url else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

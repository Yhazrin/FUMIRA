import CoreText
import SwiftUI
import UIKit

enum PosterTypography {
    /// Semantic Apple type styles for interface copy. These scale with the
    /// user's Dynamic Type setting and keep FUMIRA aligned with iOS hierarchy.
    /// FUMIRA's functional UI deliberately uses the normal SF family. It is
    /// quieter beside imagery, reads like an Apple interface, and keeps the
    /// display lettering reserved for the moments that need poster character.
    static let screenTitle = Font.system(.title2, weight: .semibold)
    static let sectionTitle = Font.system(.headline, weight: .semibold)
    static let cardTitle = Font.system(.title3, weight: .semibold)
    static let metric = Font.system(.title2, weight: .semibold)
    static let body = Font.system(.body, weight: .regular)
    static let supporting = Font.system(.subheadline, weight: .regular)
    static let label = Font.system(.subheadline, weight: .semibold)
    static let caption = Font.system(.caption, weight: .medium)
    static let button = Font.system(.body, weight: .semibold)

    /// Connection-screen brand mark — Caveat Brush when the bundled face loads,
    /// otherwise rounded SF so the invite never falls back to an empty glyph.
    static let wordmark = script(68)
    static let accent = Font.system(.title3, design: .rounded, weight: .semibold)
    static let handwrittenTitle = display(26)

    /// Fixed sizing is reserved for artwork that must preserve its poster
    /// composition, such as exports and multicolour keyword lettering.
    static func display(_ size: CGFloat) -> Font {
        _ = BundledFonts.registration
        if BundledFonts.markerGothicAvailable {
            return .custom(BundledFonts.markerGothicName, size: size)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }

    static func script(_ size: CGFloat) -> Font {
        _ = BundledFonts.registration
        if BundledFonts.caveatBrushAvailable {
            return .custom(BundledFonts.caveatBrushName, size: size)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
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

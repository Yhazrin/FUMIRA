import SwiftUI

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

    /// Rounded SF is an expressive accent, not the default interface face.
    static let wordmark = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let accent = Font.system(.title3, design: .rounded, weight: .semibold)

    /// Fixed sizing is reserved for artwork that must preserve its poster
    /// composition, such as exports and multicolour keyword lettering.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func script(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}
